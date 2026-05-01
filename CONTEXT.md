# CodexFlow Context

## Glossary

### Session Overview Home

The Session Overview Home is the mobile entry screen for session counts, not a session list.

It should show high-level entry points for total sessions, loaded sessions, and running sessions. Selecting one opens a filtered Session Browser.

### Session Browser

The Session Browser is the second-level mobile screen for choosing a session.

It should show sessions sorted by most recent update first, include the full working directory path, include history surfaced from upstream resume-style session discovery, and support keyword search across session identity, path, branch, source, and preview text.

### Chat Timeline

The Chat Timeline is the session detail surface optimized for conversation.

It should present turns as a chronological message stream with the newest content at the bottom. Turn ids and statuses are metadata, not the primary grouping users navigate by.

### Codex Agent Skill

A Codex Agent Skill is a local `SKILL.md` instruction package available to the Codex CLI runtime on the host machine.

CodexFlow should surface Codex Agent Skills from the host runtime, not treat the chat composer skill menu as a fixed set of frontend shortcuts.

### Execution Details

Execution Details are the non-conversational artifacts inside a turn, including reasoning summaries, plans, command executions, file changes, diffs, tool calls, and pending approval blocks.

The Chat Timeline should collapse Execution Details by default. Users should be able to expand details for a specific turn without expanding every turn.

### Expanded Persistent Status Notification

An Expanded Persistent Status Notification is the expanded Android foreground-service notification for Mobile Background Monitoring.

Its collapsed state should remain concise, while its expanded state should show multiple status lines such as agent reachability, host, managed session count, pending manual action count, and the dashboard shortcut.

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
