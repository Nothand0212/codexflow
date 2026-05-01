# Mobile UI Modernization Design

## Status

Drafted on 2026-05-02 after user review of the mobile UI direction. This spec captures the first modernization phase for CodexFlow Android: a light, compact, chat-first control surface for working with the local Codex CLI runtime through the CodexFlow Agent.

Project terms used by this spec are defined in `CONTEXT.md`:

- Session Overview Home
- Session Browser
- Chat Timeline
- Chat Media Attachment
- Codex Agent Skill
- Execution Details
- Expanded Persistent Status Notification
- Manual Action Required

## Context

The user runs Codex CLI on a laptop and uses CodexFlow from Android over Tailscale. The Android app must feel like a practical remote control for the laptop Agent, not like a debug console or a turn-inspection tool.

Earlier iterations exposed too much internal structure: home/list surfaces were visually busy, Chat Timeline content was grouped around turns, Execution Details competed with final Agent replies, and uploaded images were only transient composer previews. The user wants a modern Android UI that is compact, readable, and closer to WhatsApp/WeChat density while preserving CodexFlow-specific controls such as Skills, image uploads, session takeover, running state, and Manual Action Required.

## Goals

1. Redesign the first phase around three core surfaces: Session Overview Home, Session Browser, and Chat Timeline.
2. Make the Session Overview Home status-first, with total/loaded/running as entry tiles rather than inline session lists.
3. Make the Session Browser the only second-level list surface, sorted by most recent update first and searchable.
4. Make the Chat Timeline a compact chronological conversation surface with newest content visible by default.
5. Hide Execution Details from the default Chat Timeline and show only final replies plus lightweight actionable state.
6. Keep Skills and add-image controls in the same composer action area.
7. Show user and Agent Chat Media Attachments inline in the message history and keep them persistent with the owning session.
8. Visually refresh the Expanded Persistent Status Notification so it communicates status with compact icon-supported lines.

## Non-Goals

- No full dark theme in this phase.
- No desktop/tablet redesign beyond responsive constraints needed for Android and Web sanity.
- No public relay, cloud sync, or push notification architecture change.
- No full Execution Details viewer in the first chat redesign.
- No automatic rendering of arbitrary local filesystem paths from Agent text as images.
- No marketing-style landing page, decorative hero, or illustration-heavy shell.

## Visual Direction

The approved direction is Quiet Command Center.

The UI should be light, calm, compact, and operational. It should feel like a high-quality mobile control console for a local AI runtime: restrained surfaces, clear hierarchy, high contrast body text, and minimal ornament. The memorable trait should be the sense of "remote agent control in your pocket," not a generic card dashboard.

Design constraints:

- Light-only palette for this phase.
- Use compact density: smaller headers, tight row spacing, and no large empty card stacks.
- Prefer familiar icons for actions: refresh, search, add image, Skills, send, stop, approvals, dashboard.
- Use cards only for repeated items, modals, and genuinely framed tool controls.
- Avoid nested cards, decorative orbs, heavy gradients, and one-hue color dominance.
- Use high contrast for secondary labels; previous muted text was too close to the background.
- Keep text selectable in Chat Timeline.

## Information Architecture

### Session Overview Home

The first screen is not a session list. It has two bands:

1. Agent status strip
2. Three entry tiles: total sessions, loaded sessions, running sessions

The status strip is the primary first-screen information. It should show:

- online/offline state
- Agent host or base URL host
- running work count
- pending Manual Action Required count
- last refresh time

The three entry tiles open Session Browser filters:

- Total sessions: only user-initiated sessions, excluding sub-agent sessions when the backend can classify them.
- Loaded sessions: loaded/managed sessions for the selected Agent.
- Running sessions: active non-ended sessions, especially those with `lastTurnStatus == inProgress` or waiting state.

The home screen may include a small Agent switcher and new-session entry, but these should not dominate the first viewport.

### Session Browser

The Session Browser is the second-level screen for choosing a session. It must:

- sort sessions by `updatedAt` descending
- show the full working directory path
- include resume-discovered history equivalent to Codex CLI `/resume` results when the backend exposes it
- support keyword search across display name, preview, cwd, branch, source, lifecycle stage, status, model provider, and id
- keep list rows compact enough for repeated use on a phone

Rows should display:

- session title derived from explicit name, agent nickname, cwd basename, or preview
- full cwd in a monospace or path-optimized small style
- update time
- compact status pill
- short preview only when useful
- lightweight tags for loaded/managed, source, branch, and pending action state

The visual hierarchy should put title, path, and state first. The row should not look like a mini dashboard.

### Chat Timeline

The Chat Timeline is the main work surface. It should behave like a chat app:

- newest content is visible by default after opening a session
- user messages align right
- Agent final replies align left
- message bubbles are compact and selectable
- composer is fixed at the bottom
- header is compressed and does not occupy the height of a card-heavy detail panel
- loading older history is explicit and incremental
- long histories must not be fully loaded into the visible widget tree on first open

Execution Details must be completely hidden from the default Chat Timeline. The timeline should render only:

- `userMessage`
- `agentMessage`
- Chat Media Attachments attached to either message type
- Agent processing indicator while the latest turn is running
- lightweight Manual Action Required, error, or interruption status blocks

The Agent processing indicator should be animated and compact, similar in role to chat typing/working indicators. It should communicate that the Agent received the message and is still processing without exposing hidden reasoning.

When a session is ended or not loaded, the takeover/resume state should be a compact bottom action panel, not a large explanatory card in the message stream.

## Composer And Skills

The composer action area should contain:

- Skills button
- add image button
- selected image count or thumbnails
- text input
- send/steer button
- stop/end affordance when relevant

The Skills sheet should behave like a command palette:

- refreshed from the host Codex runtime whenever the app opens or refreshes dashboard data
- sorted alphabetically by skill name
- searchable by name, description, and insert text
- compact list rows with an icon, skill name, and short description
- inserting a skill should place its insert text at the current cursor position

The add-image flow should keep the current immediate thumbnail preview before sending, but sending must also attach the images to the stored Chat Timeline history.

## Chat Media Attachments

Chat Media Attachments are part of session history, not temporary upload previews.

User-uploaded images must render inline under the sent user message. Agent-produced images must render inline under the Agent reply when the backend marks them as structured media or when the reply contains Markdown image links that the renderer can safely display.

Thumbnail behavior:

- show thumbnails inside or directly below the owning bubble
- preserve aspect ratio with stable max dimensions
- tap opens a larger preview
- failed media loads show a compact broken-media state with filename or source label
- media should not resize surrounding layout unexpectedly after load

Persistence behavior:

- image uploads can remain temporary while they are only composer drafts
- once a message is submitted, referenced uploads must be copied into CodexFlow-managed persistent media storage
- media URLs served to the app must be session-scoped and not expose arbitrary local filesystem paths
- Markdown image links may be rendered when they are explicit image links
- plain local paths inside Agent text are file references unless the backend explicitly marks them as media

This preserves safety and avoids accidentally exposing local files just because the Agent mentioned a path.

## Expanded Persistent Status Notification

The notification design should match the UI direction without trying to become a full dashboard.

Collapsed state:

- one concise title
- one concise status line
- icon-supported action affordances when Android/launcher permits it

Expanded state:

- title: CodexFlow or selected Agent name
- details: online/offline, host, managed session count, running count, pending Manual Action Required count, recently running session labels, last check time
- action buttons: dashboard, approvals, refresh

The notification should use Android-native icons and short labels. Text-only notification layouts are acceptable as a platform fallback, but the APK resources should include icons so supported launchers can display them.

## Data And API Requirements

### Session Classification

The backend should preserve `userInitiated` or an equivalent classification so the Session Overview Home can count only user-started sessions under Total sessions. Sub-agent sessions should remain available for diagnostics later, but they should not inflate the user-facing total in this phase.

### Session Browser Source Data

The dashboard/session discovery API should provide enough data to match the user expectation from Codex CLI `/resume`:

- stable session id
- full cwd
- updatedAt
- source
- loaded/runtime availability
- resume availability and blocked reason
- branch/model metadata when available
- userInitiated classification

### Timeline Paging

The session detail API should support loading a recent window first and loading earlier turns incrementally. The mobile client should keep the visible message list bounded and request older history only when the user taps "load earlier messages."

### Media Data Shape

The API should add a structured media list to timeline items rather than encoding media only inside text. A first-version shape can be:

```json
{
  "items": [
    {
      "id": "item_123",
      "type": "userMessage",
      "body": "Please inspect this screenshot.",
      "media": [
        {
          "id": "media_123",
          "kind": "image",
          "name": "screenshot.jpg",
          "mimeType": "image/jpeg",
          "url": "/api/v1/sessions/session_123/media/media_123",
          "width": 1280,
          "height": 720
        }
      ]
    }
  ]
}
```

The Flutter model should parse the structured list and the Chat Timeline should render it. The backend may also derive structured media entries from safe Markdown image links for Agent replies.

## Accessibility And Responsiveness

- Body text should remain readable at Android default font scale.
- Bubble width should be capped around 78-82% of screen width.
- Buttons must keep stable touch targets and not change size when labels or loading states change.
- Secondary text must pass visual contrast against the current background.
- Long paths should ellipsize or wrap intentionally; they must not overflow row boundaries.
- Text in Chat Timeline must remain selectable/copyable.
- Empty, loading, offline, and error states must use the same compact visual language as normal states.

## Implementation Touchpoints

Likely implementation areas:

- `flutter/codexflow/lib/theme/palette.dart`
- `flutter/codexflow/lib/widgets/common.dart`
- `flutter/codexflow/lib/screens/dashboard_screen.dart`
- `flutter/codexflow/lib/screens/session_detail_screen.dart`
- `flutter/codexflow/lib/models/app_models.dart`
- `flutter/codexflow/lib/state/app_model.dart`
- `flutter/codexflow/lib/services/api_client.dart`
- `internal/httpapi/image_uploads.go`
- Go session detail serialization code that emits `TurnItem`
- Android notification Kotlin resources and formatter classes

The implementation should avoid large rewrites unrelated to these surfaces.

## Verification

Manual verification:

- Open Android app from a fresh start and confirm the home screen shows status first and only three main entry tiles.
- Tap total/loaded/running and confirm each opens a filtered Session Browser.
- Confirm Session Browser sorting is newest-first and search matches cwd, branch, title, source, and preview.
- Open a long session and confirm the latest message is visible without manual scrolling.
- Confirm older history loads incrementally.
- Send a text message and confirm only final Agent replies appear, not reasoning or tool details.
- Send a message with an image and confirm the image appears in history after refresh/reopen.
- Confirm Agent Markdown image replies render inline when safe.
- Tap a thumbnail and confirm large preview works.
- Confirm text selection/copy works in Chat Timeline.
- Confirm Skills refresh on app open/refresh, sort alphabetically, and search.
- Confirm collapsed and expanded notification content remains useful on the target Android device.

Automated verification:

- Flutter model tests for media parsing and session filtering.
- Flutter widget tests for Chat Timeline item rendering, Skills sheet sorting/searching, and bounded timeline windows.
- Go tests for upload persistence, media serving path safety, and session detail media serialization.
- Existing Android monitor tests for persistent status formatting and notification actions.
