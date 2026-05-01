# Android APK Build and Notifications Design

## Status

Drafted on 2026-05-01 after user review of the design direction. Revised through six review rounds addressing Android platform constraints, notification state machine, release signing, rollout, and edge cases.

## Context

CodexFlow lets a mobile client control and monitor a local Codex CLI runtime through the Go Agent. The user is currently using CodexFlow through Tailscale from Android and Web.

The Android APK currently available on the local Web download page was hot-patched for network access, but it was not rebuilt from the latest Flutter source. As a result, the Android app can show the total session count while missing the list of discovered historical sessions. The Web build and Flutter source already contain the intended history-list fix.

The current Flutter app polls `/api/v1/dashboard` while the app UI is open. The Agent already exposes `/api/v1/events` SSE, but the Android client does not consume it yet. Android also has no notification channels, notification permission flow, foreground service, persistent status notification, or alert notification routing.

Project terms used by this spec are defined in `CONTEXT.md`:

- Manual Action Required
- Mobile Background Monitoring
- Persistent Status Notification
- Mobile Notification Scope

## Goals

1. Install a reproducible local Flutter build environment on the laptop.
2. Build a new Android APK from the current Flutter source and publish it for phone installation.
3. Ensure the Android APK includes the history session list fix, especially `discovered` sessions.
4. Add Android background monitoring through a foreground service with a persistent status notification.
5. Notify the user with sound when a new manual action is required.
6. Notify the user with sound when a managed turn completes or is interrupted.
7. Route notification taps to the relevant CodexFlow screen.
8. Version the Android APK so the installed build and downloadable artifact can be identified.

## Non-Goals

- No public relay, cloud push service, FCM, APNs, or device pairing.
- No SSE-based Android background connection in this iteration.
- No notification alerts for historical, discovered, or ended sessions unless they are resumed into a managed session and receive new events, or unless they were managed in the previous poll and their final turn result became visible during the transition out of `managed`.
- No alerts for requests handled by Codex auto-approval.
- No custom audio file for the first version; Android system notification sound is sufficient.
- No iOS notification implementation in this spec.
- No auto-start after device reboot in this version.

## Confirmed Decisions

### Scope

Build environment setup, APK rebuild, history-list fix validation, alert notifications, and persistent status notification are one feature area. They should be designed and implemented together because they share Android packaging, permissions, service lifecycle, and monitoring logic.

### Manual Action Required

Only requests that remain in the Agent pending request queue require manual action. Requests that an automatic approval policy resolves before they are exposed to the client must not trigger mobile notifications.

### Background Monitoring

Android must use a foreground service for real background monitoring. Best-effort background polling is not enough for this use case.

The service must not use foreground service type `dataSync`. Android 15 applies a time limit to `dataSync` foreground services for apps targeting Android 15+, which makes it a poor fit for a long-lived monitoring service.

The first version should use foreground service type `specialUse` with an explicit subtype explaining that CodexFlow monitors a user-configured local or Tailscale Agent endpoint. `connectedDevice` is not the first choice because CodexFlow is not managing a direct hardware device connection, and using it would require unrelated connected-device permissions or runtime prerequisites.

The first APK should target Android 15:

```text
targetSdkVersion = 35
```

Minimum supported Android version should stay aligned with Flutter's project default unless implementation discovers a plugin requires a higher floor. The expected first-version floor is:

```text
minSdkVersion = 21
```

On Android versions below API 34, `foregroundServiceType="specialUse"` and `FOREGROUND_SERVICE_SPECIAL_USE` are ignored by the platform. The service should still run as a normal foreground service there; the implementation should not add low-version special-case logic beyond standard runtime API guards.

If the installed Flutter stable defaults to a different target SDK, the Android Gradle configuration should override the target explicitly for this release and install the matching Android SDK platform if needed.

### Monitored Sessions

Only currently managed sessions are eligible for alert notifications, with one explicit exception: a session that was managed in the previous poll and just transitioned out of `managed` in the current poll can emit one final turn result alert if its final `lastTurnStatus` is now `completed` or `interrupted`.

When monitoring starts, the Android app must build a baseline from the current dashboard and must not notify for:

- already pending approvals
- already completed turns
- already interrupted turns
- historical `history_only`, `discovered`, or `ended` sessions

The transition exception only applies to sessions that were already observed as managed after monitoring started.

### Event Source

The first Android notification implementation should poll `/api/v1/dashboard`.

SSE remains a later enhancement for lower latency UI refresh, but it is not required for the first reliable Android background implementation.

Polling must use adaptive intervals:

- app visible and last poll succeeded: 10 seconds
- app background and last poll succeeded: 30 seconds
- consecutive failures: exponential backoff of 30 seconds, 60 seconds, then 120 seconds max
- first success after failure resets the interval to the foreground/background success interval

The monitoring service gets app visibility from Flutter. `HomeShell` or an equivalent app-level widget should implement `WidgetsBindingObserver` and send lifecycle changes to the native monitor through the same method-channel boundary used for monitor configuration:

```text
resumed -> visible
inactive / paused / hidden / detached -> background
```

Kotlin `ProcessLifecycleOwner` is not the first-version source of truth because the existing app state and Agent URL live in Flutter, and keeping lifecycle/config signals in the same Flutter-to-native boundary is simpler to test. If a plugin supplies equivalent foreground/background callbacks, the implementation can wrap them behind the same monitor-facing interface.

Because the first version polls dashboard summaries instead of consuming a full event stream, it can only alert for the latest state visible at each poll. If a managed session completes turn A, starts turn B, and completes turn B between two polls, the monitor may only alert for turn B. This is an accepted limitation of the poll-based first version and is one reason SSE/event-stream monitoring remains future work.

### Notification Navigation

Notification taps should deep-link inside the app:

- manual action notification: open the approval surface focused on the matching approval when it is still present; otherwise open the approval list
- turn completion/interruption notification: open the matching session detail
- persistent status notification: open the dashboard

If the app is cold-started from a notification, it must apply the navigation target after the app shell and `SharedPreferences` are ready. It must not wait for a successful dashboard response before showing the target screen.

### Notification Channels

Create three Android notification channels:

1. `manual_action`
   - high importance
   - sound enabled
   - vibration enabled
   - used for new pending manual actions

2. `turn_result`
   - default importance
   - sound enabled
   - used for managed turn completed/interrupted alerts

3. `persistent_status`
   - low importance
   - silent
   - used for the foreground service persistent notification

Android notification channel behavior is sticky after first creation. If channel defaults need to change later, the implementation should use a new channel id.

### Persistent Status Content

The persistent notification should show:

- connection state: online or offline
- running managed session count
- pending manual action count
- Agent host/port

Example:

```text
CodexFlow online · running 1 · pending 0
100.91.5.116:4318
```

Total session count should stay in the app UI, not the persistent notification.

## Architecture

### Flutter Build Environment

Install Flutter stable under:

```text
/home/lin/.local/share/flutter
```

The build commands should call Flutter by absolute path:

```text
/home/lin/.local/share/flutter/bin/flutter
```

Use the existing Android SDK at:

```text
/home/lin/Android/Sdk
```

The current local SDK contains `android-36.1`. The implementation must ensure an Android 15 SDK platform is available for the chosen target:

```text
platforms;android-35
```

Build configuration should set a visible app version in `pubspec.yaml`, for example:

```yaml
version: 0.2.0+2
```

The semantic version (`0.2.0`) should be visible in the app settings screen. The build number (`2`) should map to Android `versionCode`.

The build should produce a release APK and copy the installable artifact to:

```text
/home/lin/.local/share/codexflow-web/web/codexflow-android-v0.2.0.apk
```

Also copy/update a convenience alias:

```text
/home/lin/.local/share/codexflow-web/web/codexflow-android-latest.apk
```

The Web download directory should include enough information for the user to see the latest APK version and build time.

Do not reuse Flutter Web's generated `version.json` for APK metadata because Flutter builds can overwrite it. Publish Android APK metadata to:

```text
/home/lin/.local/share/codexflow-web/web/codexflow-android-latest.json
```

If the Web UI or static `index.html` has a hard-coded Android APK download link, update it to point at `codexflow-android-latest.apk` and display or link the version metadata. The new versioned APK must be reachable from the same Web directory where `index.html` is served.

The existing hot-patched APK should not be treated as the source of truth once a rebuilt APK exists.

### APK Signing

Release APKs must not use the debug signing key.

Create a dedicated CodexFlow release keystore on the build machine:

```text
/home/lin/.local/share/codexflow-keys/release.jks
```

Create `flutter/codexflow/android/key.properties` with:

```properties
storeFile=/home/lin/.local/share/codexflow-keys/release.jks
storePassword=<local secret>
keyAlias=codexflow
keyPassword=<local secret>
```

The Android Gradle config should load `key.properties` and use that signing config for `release`.

First rollout creates the keystore. Later rollouts must reuse the same keystore so Android accepts APK updates without uninstalling the app.

The keystore and signing property files must not be committed. Add these ignore rules if they are not already present:

```gitignore
flutter/codexflow/android/key.properties
*.jks
*.keystore
```

If the release keystore is lost, existing installations signed with the old key cannot be upgraded in place. The user would have to uninstall and reinstall, losing app-local settings.

### Android Monitoring Service

The Android app should add an Android foreground service responsible for mobile background monitoring.

The service owns:

- starting and stopping dashboard polling
- maintaining the persistent status notification
- detecting new manual action required events
- detecting managed turn completion/interruption events
- sending alert notifications through the correct notification channel

The service must call `startForeground()` immediately when it starts, before network calls or other slow initialization. On Android 12+, a service started with `startForegroundService()` must enter foreground quickly or the app can crash. The first persistent notification can show a provisional state such as:

```text
CodexFlow starting · pending --
Loading Agent status
```

After the foreground notification is posted, the service can load SharedPreferences, parse the persisted snapshot, create the HTTP client, and start polling.

The Flutter UI should remain responsible for:

- dashboard display
- session detail display
- approval resolution
- settings and Agent URL configuration

The service and Flutter UI must share the Agent base URL through persistent local storage. The first version can use the existing `SharedPreferences` value `codexflow.baseURL`.

The service must react to Agent URL changes. Either of these designs is acceptable:

1. The service reads the latest stored Agent URL before every poll.
2. The Flutter UI notifies the service through a method channel when settings save a new Agent URL.

If the Agent URL changes, the service must:

- switch to the new URL without requiring a manual service restart
- reset the HTTP client state
- create a fresh baseline for the new URL
- avoid emitting alerts from the first successful poll against the new URL

### Dashboard Data Relationships

`DashboardResponse.sessions` and `DashboardResponse.approvals` are separate top-level arrays.

Approvals are not nested under sessions. The app must associate approvals with sessions by this rule:

```text
PendingRequestView.threadId == SessionSummary.id
```

When a notification payload needs a `sessionId` for a manual action, it must use:

```text
sessionId = approval.threadId
```

Managed-session notification filtering must therefore use a two-step process:

1. Build the managed session id set from `dashboard.sessions` where `session.lifecycleStage == "managed"`.
2. Filter `dashboard.approvals` to approvals whose `approval.threadId` is in that managed session id set.

Pending manual action count means the count of this filtered approval list, not the raw global approvals length.

If `SessionSummary.pendingApprovals` disagrees with the filtered approval list, notification logic must trust the filtered approval list. The filtered list carries stable approval ids for routing and deduplication; `SessionSummary.pendingApprovals` is only a display summary and can be stale during dashboard races or auto-approval transitions.

### Foreground Service Type and Permissions

The Android manifest must declare a foreground service using `specialUse`.

Required permissions:

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
```

The service declaration must include:

```xml
<service
    android:name=".CodexFlowMonitorService"
    android:exported="false"
    android:foregroundServiceType="specialUse">
    <property
        android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
        android:value="monitor_codexflow_agent_over_user_configured_tailscale_or_lan_url" />
</service>
```

Do not declare or use `dataSync` for this monitoring service. `FOREGROUND_SERVICE_DATA_SYNC` is only required if a future implementation deliberately uses `dataSync`, which this spec rejects.

At runtime, the service must call `startForeground` with the matching `FOREGROUND_SERVICE_TYPE_SPECIAL_USE` flag on Android versions that require typed foreground service starts.

### Polling Loop

The service polls `/api/v1/dashboard` using the adaptive interval defined in the Event Source section.

On every poll:

1. Read the current Agent URL.
2. Fetch the dashboard with a 15 second HTTP request timeout.
3. Filter sessions to `lifecycleStage == "managed"` and build a managed session id set.
4. Filter the global `dashboard.approvals` list by `approval.threadId in managedSessionIds`.
5. Build current state:
   - managed running count from managed sessions
   - pending manual action count from the filtered approvals
   - approval ids from the filtered approvals
   - last turn id/status by managed session
6. Check sessions that existed as managed sessions in the previous snapshot but are no longer managed in the current dashboard. If the current dashboard still contains one of those sessions in `ended`, `history_only`, `discovered`, or `runtime_available` and its `lastTurnStatus` has newly become `completed` or `interrupted`, collect it into `newTurnResults`.
   - Build the normal `turnResultKey`.
   - If `seenTurnResults` already contains that key, do not collect it.
   - If the result is collected, immediately add that key to `seenTurnResults`.
   - Remove that session from `managedTurnState` before persisting the next snapshot.
   - If the session no longer exists anywhere in the current dashboard, do not collect it because the final status cannot be confirmed.
7. Update the persistent status notification.
8. Compare current managed session state with the previous snapshot and collect any new managed turn results into the same `newTurnResults` collection.
9. Build `newManualActions` from filtered approvals and apply notification batching once per collection. Emit at most one manual action notification and at most one turn result notification for the whole poll cycle.
10. Store the current snapshot as the next baseline.

If the dashboard response is valid and contains empty `sessions` and `approvals`, treat it as an online empty state:

- persistent notification shows online, running 0, pending 0
- no alerts are emitted
- existing seen approval/turn keys are retained

If the Agent restarts and sessions temporarily disappear, this must not cause duplicate notifications when those sessions reappear.

At the end of every successful poll, after the transition check runs, `managedTurnState` should contain only current managed session ids. Remove entries for sessions that are no longer managed, including sessions that disappeared from the dashboard entirely.

If the Agent cannot be reached:

- persistent notification shows offline
- alert notifications are not emitted for connection failures in the first version
- polling continues with exponential backoff so the service can recover when Tailscale or network connectivity returns
- the persisted snapshot is not discarded
- timeout is treated as a failed poll and enters the same backoff path

### Baseline and Deduplication

The service must persist its monitoring snapshot locally, not only in memory.

Use `SharedPreferences` for the first version. Store one JSON string under a stable key such as:

```text
codexflow.monitor.snapshot.v1
```

This is acceptable because the data is small: a handful of URL snapshots containing approval ids, turn keys, timestamps, and counters. Do not write the snapshot on a tight timer; write only after a poll changes snapshot state.

Use synchronous SharedPreferences writes for the snapshot. On Android native code this means `commit()` rather than `apply()`. The snapshot is part of notification deduplication state, so accepting an asynchronous-write loss window would cause duplicate or missed alerts after process death.

The JSON object should be keyed by Agent URL. Each URL entry contains:

- initialized/baselined state
- manually stopped flag
- last used timestamp
- seen approval ids with first-observed timestamps
- last observed managed turn status by `session.id + lastTurnId`, with first-observed timestamps for terminal result keys
- last successful dashboard timestamp
- last known running managed session count
- last known pending manual action count
- previously managed session turn state, keyed by `session.id`

Shape:

```json
{
  "version": 1,
  "urls": {
    "http://100.91.5.116:4318": {
      "initialized": true,
      "manuallyStopped": false,
      "lastUsedAt": 1777615200,
      "lastSuccessAt": 1777615200,
      "seenApprovals": {
        "req-000123": 1777615200
      },
      "seenTurnResults": {
        "019-session:019-turn:completed": 1777615200
      },
      "managedTurnState": {
        "019-session": {
          "lastTurnId": "019-turn",
          "lastTurnStatus": "inProgress"
        }
      },
      "lastRunningManagedCount": 1,
      "lastPendingManualActionCount": 0
    }
  }
}
```

On service start:

- if monitoring is re-enabled after the user manually stopped it, clear the manual-stopped flag and treat the first successful dashboard response as a fresh baseline without alerting
- if a persisted snapshot exists for the current Agent URL, compare the first successful dashboard response against it and notify for new eligible events
- if no persisted snapshot exists for the current Agent URL, the first successful dashboard response becomes the baseline and emits no alert notifications

Whenever a fresh baseline is created, populate `managedTurnState` from the current managed sessions' `lastTurnId` and `lastTurnStatus`. This applies to first start, manual re-enable after stop, URL switch, and unsupported snapshot version recovery. The next poll can then detect a managed session that transitions out of `managed`.

This prevents system-kill-and-restart cycles from swallowing events that happened while the service was down.

Manual stop is different from process death. When the user explicitly stops monitoring, CodexFlow accepts that events during the stopped period are not monitored and should not be backfilled as alerts when monitoring is turned on again.

If the persisted snapshot JSON `version` is missing or unsupported, discard the snapshot and treat the next successful dashboard response as the first baseline.

Manual action alerts are deduplicated by `approval.id`.

Turn result alerts are deduplicated by:

```text
turnResultKey = session.id + ":" + lastTurnId + ":" + lastTurnStatus
```

Use `:` as the separator in persisted snapshots and tests.

Only these statuses produce turn result alerts:

- `completed`
- `interrupted`

If a turn status is missing or empty, no alert should be emitted.

Persisted snapshot data should be pruned so it cannot grow forever:

- approval ids older than 7 days can be dropped
- turn result keys older than 7 days can be dropped
- entire Agent URL snapshot entries whose `lastUsedAt` is older than 30 days can be dropped

### History Session List Fix

The dashboard list must include Codex `discovered` sessions in the history section.

The desired grouping is:

- `managed` -> managed group
- `ended` -> ended group
- `runtime_available` -> attachable runtime group
- `history_only` or `discovered` -> history group

This rule should be covered by a test so future APK builds cannot regress to a total-only dashboard.

### Notification Payloads and Routing

Every notification should carry a route target:

```text
dashboard
approvals
sessionDetail
```

Manual action notification payload:

```json
{
  "target": "approvals",
  "approvalId": "req-000123",
  "sessionId": "019..."
}
```

Turn result notification payload:

```json
{
  "target": "sessionDetail",
  "sessionId": "019...",
  "turnId": "019...",
  "status": "completed"
}
```

Persistent notification payload:

```json
{
  "target": "dashboard"
}
```

The app should introduce a navigation target abstraction so notifications can switch the bottom tab and open session detail after startup.

Notification tap routing applies to both cold-start and warm-start cases. The Android activity must use `singleTop` or an equivalent launch mode / intent handling strategy so tapping a notification does not create duplicate app instances.

Tap routing must not depend on a successful dashboard fetch before showing UI:

1. Start the app shell.
2. Apply the notification target immediately.
3. Show loading state for target-specific data.
4. If dashboard/session loading fails, keep the user on the target screen and show the existing connection error state.
5. If the target approval no longer exists, show the approval list with a short in-app notice.
6. If the target session cannot be loaded, show the dashboard with a short in-app notice.

Warm-start taps use the same rules. If the app is already open and the approval was resolved from Web or the session ended before the tap is handled, the app should apply the same fallback behavior instead of doing nothing.

### Notification Identity and Batching

Use stable notification ids:

```text
persistent_status = 1000
manual_action_alert = 2000
turn_result_alert = 3000
```

The persistent status notification always updates id `1000`.

For alert notifications, each poll cycle emits at most:

- one manual action notification
- one turn result notification

If exactly one new manual action is detected, notification id `2000` targets that approval. If multiple new manual actions are detected in the same poll, notification id `2000` says how many require attention and opens the approval list.

If exactly one new turn result is detected, notification id `3000` targets that session detail. If multiple turn results are detected in the same poll, notification id `3000` summarizes the count and opens the dashboard.

Exception: if multiple turn results are detected in the same poll and all belong to the same `session.id`, notification id `3000` should still open that session detail.

Updating notification id `2000` or `3000` for newly detected events must alert again with sound/vibration. The implementation should explicitly disable "only alert once" behavior for alert notifications. For Android APIs or notification libraries that expose this directly, use `setOnlyAlertOnce(false)` or the equivalent.

Repeated polls for the same approval id or same `session.id + lastTurnId + lastTurnStatus` must update state without re-alerting.

### Android Notification Permission

The app should request notification permission at runtime on Android 13+ before alert notifications are expected to work. If the user denies notification permission:

- foreground service still needs a persistent notification where Android requires it
- alert notifications may not be visible
- the app should show an in-app settings notice rather than failing silently

The monitoring service can still run, but the settings screen must show that alert notifications are disabled until the permission is granted.

Permission request timing:

- Do not request notification permission on first app launch.
- Request it when the user first enables or starts background monitoring, after the Agent URL is configured.
- If monitoring starts automatically after app launch and permission has never been requested, show an in-app prompt explaining that CodexFlow needs notification permission for manual action and turn result alerts; the prompt action triggers the Android permission request.
- If permission is denied, continue monitoring and keep the settings warning visible.

On Android 13+, the foreground service persistent notification can still be shown in the system's foreground service surfaces even when `POST_NOTIFICATIONS` is denied. The implementation must not skip `startForeground()` because alert-notification permission is missing. `POST_NOTIFICATIONS` controls alert visibility, not whether the foreground service enters foreground state.

### Flutter and Native Boundary

Two implementation choices are acceptable:

1. Use a maintained Flutter plugin for foreground service and local notifications.
2. Implement the foreground service and notification code in Android Kotlin, with a small Flutter method-channel boundary for configuration and navigation.

The implementation plan should choose the lower-risk option after checking current plugin compatibility with the installed Flutter stable and Android Gradle Plugin. The first preference is a maintained plugin if it supports:

- Android foreground service
- notification channels
- notification tap callbacks
- stable release APK builds

If plugin compatibility is poor, prefer a small Kotlin implementation over fighting plugin behavior.

### Release Shrinking

Release APK builds must verify whether code shrinking and obfuscation are enabled by the selected Flutter/Android configuration.

If Kotlin native service code or method channels are used, add keep rules as needed for:

- `CodexFlowMonitorService`
- any notification receiver or tap callback Activity/receiver
- method-channel entrypoints invoked from Flutter or Android

The manifest `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE` property must remain in the merged manifest. The build verification should inspect the merged or packaged manifest, not rely on source files alone.

## User Experience

### Settings

The settings screen should expose notification/monitoring status:

- Agent URL
- app version and build number
- background monitoring enabled/disabled
- notification permission status
- foreground service running status

The first version starts monitoring automatically after the app launches, and the user can stop it from settings.

Stopping monitoring means:

- Flutter UI synchronously writes `manuallyStopped = true` for the current Agent URL snapshot before stopping the service
- stop dashboard polling
- stop the Android foreground service
- remove the persistent status notification
- keep the persisted snapshot but mark the current Agent URL as manually stopped

The manual-stop marker must be written by the UI before asking the service to stop. Do not rely on service `onDestroy()` for this marker, because process death or service-stop races can skip `onDestroy()`.

When monitoring is stopped, Android may reclaim the app process more aggressively. This is acceptable for this version. The next app launch should be treated as a normal cold start.

When the user manually re-enables monitoring, the first successful dashboard response becomes a fresh baseline and must not emit alerts for events that accumulated while monitoring was stopped.

This version does not auto-start monitoring after device reboot.

Changing the Agent URL in settings must reconfigure the monitoring service without requiring the user to force-stop the app.

### Alert Text

Manual action required:

```text
CodexFlow needs your action
<session label> has a pending approval
```

Multiple manual actions in one poll:

```text
CodexFlow needs your action
<count> pending approvals need review
```

Turn completed:

```text
CodexFlow task completed
<session label> finished a turn
```

Turn interrupted:

```text
CodexFlow task interrupted
<session label> was interrupted
```

Multiple turn results in one poll:

```text
CodexFlow tasks updated
<completed count> completed · <interrupted count> interrupted
```

If either count is zero, omit that segment. Examples:

```text
CodexFlow tasks updated
3 completed
```

```text
CodexFlow tasks updated
2 interrupted
```

Session label should prefer the same display logic as the dashboard: explicit name, agent nickname, directory name, preview title, then short id.

## Testing Strategy

### Dart/Flutter Tests

Add tests for:

- `discovered` sessions are included in the history group.
- global `DashboardResponse.approvals` are associated to sessions through `PendingRequestView.threadId == SessionSummary.id`.
- filtered approval list count takes precedence over `SessionSummary.pendingApprovals` when they disagree.
- managed sessions that move out of `managed` between polls still produce one turn result alert if their current dashboard summary has a newly completed/interrupted last turn.
- transition-final turn results are collected into the same `newTurnResults` collection as managed-session turn results, then batched once per poll.
- collected transition-final turn results are written to `seenTurnResults` immediately and removed from `managedTurnState` before the next snapshot is persisted.
- `managedTurnState` is pruned to current managed session ids after each successful poll.
- fresh baselines populate `managedTurnState` from current managed sessions.
- sessions that disappear entirely from dashboard do not emit final turn result alerts.
- valid empty dashboards show online running 0 pending 0 and do not clear deduplication state or duplicate later notifications.
- manual action alerts are not emitted for the initial baseline.
- persisted snapshots are loaded on service restart and new events since the previous snapshot are not swallowed.
- persisted snapshot writes use synchronous commit semantics.
- persisted snapshot JSON records timestamps for approval ids and turn result keys, then prunes entries older than 7 days.
- persisted snapshot JSON prunes URL entries whose `lastUsedAt` is older than 30 days.
- manual action alerts are emitted for new pending approvals in managed sessions.
- manual action alerts are not emitted for approvals belonging to non-managed sessions.
- turn result alerts are emitted for new completed/interrupted managed turns.
- duplicate polling responses do not re-emit the same alert.
- persistent notification summary counts online/offline, running managed sessions, and pending manual actions.
- Agent URL changes reset the baseline for the new URL and stop polling the old URL.
- Flutter lifecycle changes notify the monitor of visible/background state through the method-channel boundary.
- network failures and 15 second HTTP timeouts use 30/60/120 second backoff, and success resets the interval.
- foreground/background app visibility changes switch between 10 second and 30 second success intervals.
- stopping monitoring stops polling, stops the foreground service, removes the persistent notification, and marks the current URL as manually stopped.
- stopping monitoring writes the manual-stop marker before stopping the service and does not rely on service `onDestroy()`.
- manually re-enabling monitoring creates a fresh baseline and does not backfill alerts from the stopped period.
- unsupported snapshot versions are discarded and treated as first-start baseline.
- notification permission denied state is surfaced without crashing monitoring.
- notification tap routing handles cold start, warm start, dashboard load failure, missing approval, and missing session.
- notification id and batching logic emits at most one manual action alert and one turn result alert per poll.
- turn result deduplication key uses `session.id + ":" + lastTurnId + ":" + lastTurnStatus`.
- batch notification text is deterministic for multiple manual actions and multiple turn results.
- multiple turn results in one poll route to session detail when all results belong to the same session; otherwise route to dashboard.
- new events that update alert notification ids `2000` or `3000` re-alert rather than silently updating.

### Go Tests

No Go API change is required by this spec. Existing Agent dashboard behavior should stay compatible.

If the implementation adds backend compatibility fields or endpoints, add focused Go tests for those additions.

### Android Build Verification

Run:

```bash
/home/lin/.local/share/flutter/bin/flutter pub get
/home/lin/.local/share/flutter/bin/flutter test
/home/lin/.local/share/flutter/bin/flutter build apk --release
```

Release signing setup for the first build:

```bash
mkdir -p /home/lin/.local/share/codexflow-keys
keytool -genkeypair \
  -v \
  -keystore /home/lin/.local/share/codexflow-keys/release.jks \
  -alias codexflow \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=CodexFlow, O=Local, L=Local, C=US"
```

The implementation may wrap APK copy and metadata generation in a script, but metadata must be generated by command, not hand-edited. After build:

```bash
sha256sum /home/lin/.local/share/codexflow-web/web/codexflow-android-v0.2.0.apk
```

Use that SHA256 in `codexflow-android-latest.json`.

Then verify:

- release APK exists
- release APK is signed with the CodexFlow release keystore, not the debug keystore
- APK manifest contains network, notification, and foreground service permissions
- APK manifest declares foreground service type `specialUse` and does not declare the monitoring service as `dataSync`
- APK packaged or merged manifest contains `android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE`
- main activity launch mode prevents duplicate app instances on notification taps, for example `singleTop`
- release shrinking does not remove foreground service, notification receiver, or method-channel entrypoints
- APK installs on the Android device
- Android app can connect to `http://100.91.5.116:4318`
- dashboard shows discovered historical sessions in the history list, not just the total count
- foreground service persistent notification appears
- new manual action emits a sound notification
- managed turn completion/interruption emits a sound notification
- notification taps route to the expected screen
- settings shows app version and build number
- Web download page or static index links to `codexflow-android-latest.apk`
- Android APK metadata exists at `codexflow-android-latest.json`, not Flutter Web's generated `version.json`
- Android APK metadata includes SHA256 computed from the actual copied versioned APK.

### Android Service Verification

Verify on device or emulator:

- start monitoring from settings and confirm the foreground service notification appears
- stop monitoring from settings and confirm polling stops, the foreground service stops, and the persistent notification disappears
- stop monitoring from settings, wait for at least one poll interval while new events occur, re-enable monitoring, and confirm no backfill alerts are emitted for events that occurred while monitoring was stopped
- restart the app after stopping monitoring and confirm it cold-starts cleanly
- kill the app process while monitoring is running, relaunch, and confirm persisted snapshot state is loaded
- change Agent URL while monitoring is running and confirm subsequent polls use the new URL
- deny notification permission and confirm settings shows alert notifications disabled without crashing
- simulate Agent timeout or unreachable URL and confirm 30/60/120 second backoff behavior

## Rollout

1. Build and test locally.
2. If this is the first release build on this machine, create `/home/lin/.local/share/codexflow-keys/release.jks` and `flutter/codexflow/android/key.properties`.
3. Reuse the same release keystore for every later release build.
4. Publish the versioned APK to the local Web directory as `codexflow-android-v0.2.0.apk`.
5. Update `codexflow-android-latest.apk` to the same file contents for convenience.
6. Compute SHA256 from the copied versioned APK.
7. Generate `codexflow-android-latest.json` from the actual version, build number, artifact name, build time, and SHA256.
8. Update the local Web download page or static metadata so the user can see the APK version, build number, build time, and SHA256.
9. Keep the old hot-patched APK available only as a fallback.
10. User installs the new APK on Android.
11. Verify with Tailscale Agent URL:

```text
http://100.91.5.116:4318
```

## Versioning

The implementation must bump `flutter/codexflow/pubspec.yaml` from the current `0.1.0+1` before producing the APK.

The first notification-capable Android APK should use:

```text
0.2.0+2
```

Artifact naming:

```text
codexflow-android-v0.2.0.apk
codexflow-android-latest.apk
```

The settings screen should display:

```text
CodexFlow 0.2.0 (2)
```

The local Web download directory should include a small metadata file, such as:

```json
{
  "version": "0.2.0",
  "buildNumber": 2,
  "artifact": "codexflow-android-v0.2.0.apk",
  "sha256": "<computed during rollout>",
  "builtAt": "2026-05-01T..."
}
```

Write that metadata to:

```text
/home/lin/.local/share/codexflow-web/web/codexflow-android-latest.json
```

Do not write APK metadata to Flutter Web's generated `version.json`.

The implementation should generate this JSON as part of the APK publish step. It should not be hand-edited.

## Risks

- Android battery optimization can still stop background network work on some devices. This version mitigates that with a foreground service, adaptive polling intervals, visible service state, and explicit offline recovery.
- Notification permission denial on Android 13+ prevents alert notifications. The app must make that state visible.
- Tailscale connectivity changes may cause temporary offline status. The service should recover through polling.
- Polling dashboard summaries can miss intermediate turn results when multiple turns start and finish between two polls. This is accepted for the first version and should be revisited with SSE/event-stream monitoring.
- If the release keystore is lost, users cannot update the installed APK in place. Keep `/home/lin/.local/share/codexflow-keys/release.jks` backed up outside the repo.
- Android notification channel sound settings are sticky. Channel ids should change if sound behavior needs to change later.
- Foreground service policy differs by Android version. The implementation must verify manifest permissions and service type against the target SDK used by Flutter.
- `specialUse` is appropriate for local sideloaded builds but would require careful Play Console declaration if CodexFlow is later distributed through Google Play.

## Future Work

- SSE-based live UI refresh with polling fallback.
- FCM or relay-backed push notifications for non-Tailscale deployments.
- Per-agent or per-session notification preferences.
- Quiet hours.
- Custom notification sounds.
- Approval notification grouping when multiple approvals arrive together.
