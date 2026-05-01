# Persist Chat Media Attachments As Session History

CodexFlow will treat images attached to Chat Timeline messages as session history, not as temporary upload previews. Composer uploads may stay temporary before submission, but once a user message or Agent reply owns a media item, the backend must copy it into CodexFlow-managed persistent media storage and serve it through session-scoped media URLs.

**Considered Options**

- Keep uploads in `/tmp/codexflow/uploads` with the existing 24-hour TTL. This is simple, but history breaks after cleanup or restart and does not match chat-app behavior.
- Render any local filesystem path mentioned by the Agent as an image. This is convenient, but unsafe because Agent text can mention arbitrary files that were not intentionally shared as media.
- Persist only explicitly attached or structured media. This is the chosen option because it keeps chat history stable while preserving a clear safety boundary.

**Consequences**

The backend needs persistent media storage, session-scoped media identifiers, and path-safety checks. Flutter needs a structured media model and thumbnail/preview UI. Plain local paths in Agent text remain file references unless the backend explicitly marks them as Chat Media Attachments.
