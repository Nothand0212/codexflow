# Android APK Build and Notifications Design

## Status

Drafted on 2026-05-01 after user review of the design direction.

Revised after review to address Android 15 foreground service limits, service restart behavior, polling backoff, notification identity, test coverage, runtime APK verification, and APK versioning.

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
- No notification alerts for historical, discovered, or ended sessions unless they are resumed into a managed session and receive new events.
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

If the installed Flutter stable defaults to a different target SDK, the Android Gradle configuration should override the target explicitly for this release and install the matching Android SDK platform if needed.

### Monitored Sessions

Only currently managed sessions are eligible for alert notifications.

When monitoring starts, the Android app must build a baseline from the current dashboard and must not notify for:

- already pending approvals
- already completed turns
- already interrupted turns
- historical `history_only`, `discovered`, or `ended` sessions

### Event Source

The first Android notification implementation should poll `/api/v1/dashboard`.

SSE remains a later enhancement for lower latency UI refresh, but it is not required for the first reliable Android background implementation.

Polling must use adaptive intervals:

- app visible and last poll succeeded: 10 seconds
- app background and last poll succeeded: 30 seconds
- consecutive failures: exponential backoff of 30 seconds, 60 seconds, then 120 seconds max
- first success after failure resets the interval to the foreground/background success interval

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

The existing hot-patched APK should not be treated as the source of truth once a rebuilt APK exists.

### Android Monitoring Service

The Android app should add an Android foreground service responsible for mobile background monitoring.

The service owns:

- starting and stopping dashboard polling
- maintaining the persistent status notification
- detecting new manual action required events
- detecting managed turn completion/interruption events
- sending alert notifications through the correct notification channel

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

1. Fetch the dashboard.
2. Filter sessions to `lifecycleStage == "managed"`.
3. Build current state:
   - managed running count
   - pending manual action count for managed sessions
   - approval ids
   - last turn id/status by managed session
4. Update the persistent status notification.
5. Compare current state with the previous snapshot.
6. Emit alert notifications only for new eligible transitions.
7. Store the current snapshot as the next baseline.

If the Agent cannot be reached:

- persistent notification shows offline
- alert notifications are not emitted for connection failures in the first version
- polling continues with exponential backoff so the service can recover when Tailscale or network connectivity returns
- the persisted snapshot is not discarded

### Baseline and Deduplication

The service must persist its monitoring snapshot locally, not only in memory.

The persisted snapshot should be keyed by Agent URL and contain:

- initialized/baselined state
- seen approval ids
- last observed managed turn status by `session.id + lastTurnId`
- last successful dashboard timestamp
- last known running managed session count
- last known pending manual action count

On service start:

- if a persisted snapshot exists for the current Agent URL, compare the first successful dashboard response against it and notify for new eligible events
- if no persisted snapshot exists for the current Agent URL, the first successful dashboard response becomes the baseline and emits no alert notifications

This prevents system-kill-and-restart cycles from swallowing events that happened while the service was down.

Manual action alerts are deduplicated by `approval.id`.

Turn result alerts are deduplicated by:

```text
session.id + lastTurnId + lastTurnStatus
```

Only these statuses produce turn result alerts:

- `completed`
- `interrupted`

If a turn status is missing or empty, no alert should be emitted.

Persisted snapshot data should be pruned so it cannot grow forever. Approval ids and turn result keys older than 7 days can be dropped.

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

Cold-start routing must not depend on a successful dashboard fetch before showing UI:

1. Start the app shell.
2. Apply the notification target immediately.
3. Show loading state for target-specific data.
4. If dashboard/session loading fails, keep the user on the target screen and show the existing connection error state.
5. If the target approval no longer exists, show the approval list with a short in-app notice.
6. If the target session cannot be loaded, show the dashboard with a short in-app notice.

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

Repeated polls for the same approval id or same `session.id + lastTurnId + lastTurnStatus` must update state without re-alerting.

### Android Notification Permission

The app should request notification permission at runtime on Android 13+ before alert notifications are expected to work. If the user denies notification permission:

- foreground service still needs a persistent notification where Android requires it
- alert notifications may not be visible
- the app should show an in-app settings notice rather than failing silently

The monitoring service can still run, but the settings screen must show that alert notifications are disabled until the permission is granted.

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

## User Experience

### Settings

The settings screen should expose notification/monitoring status:

- Agent URL
- app version and build number
- background monitoring enabled/disabled
- notification permission status
- foreground service running status

The first version starts monitoring automatically after the app launches, and the user can stop it from settings.

It does not auto-start after device reboot in this version.

Changing the Agent URL in settings must reconfigure the monitoring service without requiring the user to force-stop the app.

### Alert Text

Manual action required:

```text
CodexFlow needs your action
<session label> has a pending approval
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

Session label should prefer the same display logic as the dashboard: explicit name, agent nickname, directory name, preview title, then short id.

## Testing Strategy

### Dart/Flutter Tests

Add tests for:

- `discovered` sessions are included in the history group.
- manual action alerts are not emitted for the initial baseline.
- persisted snapshots are loaded on service restart and new events since the previous snapshot are not swallowed.
- manual action alerts are emitted for new pending approvals in managed sessions.
- manual action alerts are not emitted for approvals belonging to non-managed sessions.
- turn result alerts are emitted for new completed/interrupted managed turns.
- duplicate polling responses do not re-emit the same alert.
- persistent notification summary counts online/offline, running managed sessions, and pending manual actions.
- Agent URL changes reset the baseline for the new URL and stop polling the old URL.
- network failures use 30/60/120 second backoff and success resets the interval.
- foreground/background app visibility changes switch between 10 second and 30 second success intervals.
- notification permission denied state is surfaced without crashing monitoring.
- notification tap routing handles cold start, dashboard load failure, missing approval, and missing session.
- notification id and batching logic emits at most one manual action alert and one turn result alert per poll.

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

Then verify:

- release APK exists
- APK manifest contains network, notification, and foreground service permissions
- APK manifest declares foreground service type `specialUse` and does not declare the monitoring service as `dataSync`
- APK installs on the Android device
- Android app can connect to `http://100.91.5.116:4318`
- dashboard shows discovered historical sessions in the history list, not just the total count
- foreground service persistent notification appears
- new manual action emits a sound notification
- managed turn completion/interruption emits a sound notification
- notification taps route to the expected screen
- settings shows app version and build number

## Rollout

1. Build and test locally.
2. Publish the versioned APK to the local Web directory as `codexflow-android-v0.2.0.apk`.
3. Update `codexflow-android-latest.apk` to the same file contents for convenience.
4. Update the local Web download page or static metadata so the user can see the APK version, build number, build time, and SHA256.
5. Keep the old hot-patched APK available only as a fallback.
6. User installs the new APK on Android.
7. Verify with Tailscale Agent URL:

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

## Risks

- Android battery optimization can still stop background network work on some devices. This version mitigates that with a foreground service, adaptive polling intervals, visible service state, and explicit offline recovery.
- Notification permission denial on Android 13+ prevents alert notifications. The app must make that state visible.
- Tailscale connectivity changes may cause temporary offline status. The service should recover through polling.
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
