# CodexFlow Context

## Glossary

### Manual Action Required

A request needs manual action only when the Agent has surfaced a pending request that still requires the user to respond in CodexFlow.

This includes command approvals, file change approvals, permission approvals, and structured user input requests that remain in the pending approval queue.

Requests that are handled by an automatic approval policy, such as Codex auto-approval, are not considered manual action required and should not trigger mobile notifications.

### Mobile Background Monitoring

Mobile background monitoring means the Android client keeps watching the CodexFlow Agent even when the app is not the visible foreground screen.

For Android, this should be implemented as a foreground service with a persistent status notification, not as best-effort background polling.

### Persistent Status Notification

The persistent status notification is the always-visible Android notification owned by CodexFlow's foreground service.

It should show concise Agent status, such as connection state, running session count, and pending manual action count. It is distinct from alert notifications for manual action required, turn completion, or turn interruption.

### Mobile Notification Scope

Mobile notifications should only be emitted for new changes in sessions currently managed by CodexFlow.

The Android client should build a baseline when monitoring starts and must not notify for old pending requests or historical turn states that already existed before monitoring began.

Historical, discovered, and ended sessions should stay visible in the UI, but they should not generate completion, interruption, or manual action alerts unless they are resumed into a managed session and then receive new events.
