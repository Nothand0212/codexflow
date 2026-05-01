# CodexFlow Context

## Glossary

### Session Overview Home

The Session Overview Home is the mobile entry screen for session counts, not a session list.

It should use a status-first layout: Agent reachability, host, running work, pending manual action count, and last refresh are primary first-screen information. High-level entry points for total sessions, loaded sessions, and running sessions remain on the first screen and open filtered Session Browsers.

### Session Browser

The Session Browser is the second-level mobile screen for choosing a session.

It should show sessions sorted by most recent update first, include the full working directory path, include history surfaced from upstream resume-style session discovery, and support keyword search across session identity, path, branch, source, and preview text.

### Chat Timeline

The Chat Timeline is the session detail surface optimized for conversation.

It should present turns as a compact chronological message stream with the newest content at the bottom. Turn ids and statuses are metadata, not the primary grouping users navigate by.

### Chat Media Attachment

A Chat Media Attachment is an image or media artifact that belongs to a user message or Agent reply in the Chat Timeline.

Chat Media Attachments should render inline with the owning message as thumbnails and open into a larger preview when selected.

Chat Media Attachments are session history, not temporary upload previews. Once attached to a Chat Timeline message, they should be copied into CodexFlow-managed persistent media storage and remain viewable for as long as the owning session remains available.

CodexFlow should automatically render user-uploaded images, structured media attachments, and Markdown image links from Agent replies. Local filesystem paths mentioned in Agent text should be treated as file references unless the backend explicitly marks them as media attachments.

### Codex Agent Skill

A Codex Agent Skill is a local `SKILL.md` instruction package available to the Codex CLI runtime on the host machine.

CodexFlow should surface Codex Agent Skills from the host runtime, not treat the chat composer skill menu as a fixed set of frontend shortcuts.

### Execution Details

Execution Details are the non-conversational artifacts inside a turn, including reasoning summaries, plans, command executions, file changes, diffs, tool calls, and pending approval blocks.

The Chat Timeline should hide Execution Details from the default mobile conversation surface. CodexFlow should only surface actionable state, such as Manual Action Required, errors, or interruption, as lightweight status blocks in the Chat Timeline.

### Expanded Persistent Status Notification

An Expanded Persistent Status Notification is the expanded Android foreground-service notification for Mobile Background Monitoring.

Its collapsed state should remain concise, while its expanded state should show multiple status lines such as agent reachability, host, managed session count, running turn count, pending manual action count, recently running session labels, last check time, and the dashboard shortcut.

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
