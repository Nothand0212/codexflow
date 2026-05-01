# Android APK Build and Notifications Design

## Status

Drafted on 2026-05-01 after user review of the design direction.

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

## Non-Goals

- No public relay, cloud push service, FCM, APNs, or device pairing.
- No SSE-based Android background connection in this iteration.
- No notification alerts for historical, discovered, or ended sessions unless they are resumed into a managed session and receive new events.
- No alerts for requests handled by Codex auto-approval.
- No custom audio file for the first version; Android system notification sound is sufficient.
- No iOS notification implementation in this spec.

## Confirmed Decisions

### Scope

Build environment setup, APK rebuild, history-list fix validation, alert notifications, and persistent status notification are one feature area. They should be designed and implemented together because they share Android packaging, permissions, service lifecycle, and monitoring logic.

### Manual Action Required

Only requests that remain in the Agent pending request queue require manual action. Requests that an automatic approval policy resolves before they are exposed to the client must not trigger mobile notifications.

### Background Monitoring

Android must use a foreground service for real background monitoring. Best-effort background polling is not enough for this use case.

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

### Notification Navigation

Notification taps should deep-link inside the app:

- manual action notification: open the approval surface focused on the matching approval when it is still present; otherwise open the approval list
- turn completion/interruption notification: open the matching session detail
- persistent status notification: open the dashboard

If the app is cold-started from a notification, it must apply the navigation target after `SharedPreferences` and the first dashboard load are ready.

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

The build should produce a release APK and copy the installable artifact to:

```text
/home/lin/.local/share/codexflow-web/web/codexflow-android-latest.apk
```

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

### Polling Loop

The service should poll `/api/v1/dashboard` at a fixed interval. A 10 second interval is the default.

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
- polling continues so the service can recover when Tailscale or network connectivity returns

### Baseline and Deduplication

The service must maintain an in-memory monitoring snapshot.

On service start:

- first successful dashboard response becomes the baseline
- no alert notifications are emitted from that first response

Manual action alerts are deduplicated by `approval.id`.

Turn result alerts are deduplicated by:

```text
session.id + lastTurnId + lastTurnStatus
```

Only these statuses produce turn result alerts:

- `completed`
- `interrupted`

If a turn status is missing or empty, no alert should be emitted.

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

### Android Permissions

The Android manifest should include:

- `android.permission.INTERNET`
- `android.permission.POST_NOTIFICATIONS`
- `android.permission.FOREGROUND_SERVICE`
- foreground service type permission required by the selected service type on Android 14+

The foreground service declaration should include an explicit `foregroundServiceType`. `dataSync` is the closest fit for polling the local Agent.

The app should request notification permission at runtime on Android 13+ before alert notifications are expected to work. If the user denies notification permission:

- foreground service still needs a persistent notification where Android requires it
- alert notifications may not be visible
- the app should show an in-app settings notice rather than failing silently

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
- background monitoring enabled/disabled
- notification permission status
- foreground service running status

The first version starts monitoring automatically after the app launches, and the user can stop it from settings.

It does not auto-start after device reboot in this version.

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
- manual action alerts are emitted for new pending approvals in managed sessions.
- manual action alerts are not emitted for approvals belonging to non-managed sessions.
- turn result alerts are emitted for new completed/interrupted managed turns.
- duplicate polling responses do not re-emit the same alert.
- persistent notification summary counts online/offline, running managed sessions, and pending manual actions.

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
- APK AOT artifact contains evidence of the `discovered` history handling
- APK installs on the Android device
- Android app can connect to `http://100.91.5.116:4318`
- dashboard shows historical session list, not just total count
- foreground service persistent notification appears
- new manual action emits a sound notification
- managed turn completion/interruption emits a sound notification
- notification taps route to the expected screen

## Rollout

1. Build and test locally.
2. Publish APK to the local Web directory as `codexflow-android-latest.apk`.
3. Keep the old hot-patched APK available only as a fallback.
4. User installs the new APK on Android.
5. Verify with Tailscale Agent URL:

```text
http://100.91.5.116:4318
```

## Risks

- Android battery optimization may still stop background network work on some devices. The settings screen should surface foreground service state and can later link to battery optimization settings.
- Notification permission denial on Android 13+ prevents alert notifications. The app must make that state visible.
- Tailscale connectivity changes may cause temporary offline status. The service should recover through polling.
- Android notification channel sound settings are sticky. Channel ids should change if sound behavior needs to change later.
- Foreground service policy differs by Android version. The implementation must verify manifest permissions and service type against the target SDK used by Flutter.

## Future Work

- SSE-based live UI refresh with polling fallback.
- FCM or relay-backed push notifications for non-Tailscale deployments.
- Per-agent or per-session notification preferences.
- Quiet hours.
- Custom notification sounds.
- Approval notification grouping when multiple approvals arrive together.
