# Mobile UI Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved Quiet Command Center mobile UI, including status-first home, compact session browser, chat-app timeline, persistent inline image history, searchable Skills, and richer persistent notification content.

**Architecture:** Keep the existing Flutter/Go split. The Go HTTP API becomes responsible for persisting submitted image attachments and exposing session-scoped media URLs; Flutter parses structured media fields and renders compact chat bubbles around conversation items only. UI changes stay scoped to the three core surfaces and the Android notification formatter/resources.

**Tech Stack:** Go 1.26, `net/http`, local filesystem/SQLite state directory, Flutter 3/Dart, Provider, `flutter_markdown`, Android Kotlin notification service.

---

## File Structure

- Modify `internal/config/config.go`: add a media storage directory config defaulting under `~/.codexflow/media`.
- Modify `cmd/codexflow-agent/main.go`: pass config into the HTTP server so it can use the configured media directory.
- Modify `internal/httpapi/server.go`: add media routes, return structured attachment metadata, and overlay persisted media onto session detail/start-turn responses.
- Modify `internal/httpapi/image_uploads.go`: expose enough upload metadata for durable copy into session media storage.
- Create `internal/httpapi/session_media.go`: persistent media store, manifest load/save, safe file serving, and attachment lookup by session/turn/item.
- Create `internal/httpapi/session_media_test.go`: backend tests for persistence, path safety, and attachment lookup.
- Modify `internal/runtime/models.go`: add `ChatMediaAttachment` and `TurnItem.Media`.
- Modify `internal/runtime/transform.go`: preserve any structured `media` entries already present on raw runtime items.
- Modify `internal/runtime/session_detail_pagination_test.go`: assert media survives runtime normalization.
- Modify `flutter/codexflow/lib/models/app_models.dart`: add `ChatMediaAttachment` and parse `TurnItem.media`.
- Modify `flutter/codexflow/lib/services/api_client.dart`: no endpoint rename; keep upload/start/steer payloads and rely on structured media in session detail responses.
- Modify `flutter/codexflow/lib/screens/session_detail_screen.dart`: render inline media thumbnails/previews, keep hidden Execution Details, tighten header/composer density.
- Modify `flutter/codexflow/lib/screens/dashboard_screen.dart`: status-first home layout and compact Session Browser rows.
- Modify `flutter/codexflow/lib/widgets/common.dart`: remove decorative orb background and add compact UI primitives for status strip and media states.
- Modify `flutter/codexflow/lib/theme/palette.dart`: adjust muted text/background contrast while keeping the approved light palette.
- Modify `flutter/codexflow/test/session_detail_pagination_model_test.dart`: model tests for media parsing/merge.
- Modify `flutter/codexflow/test/session_detail_screen_test.dart`: widget tests for inline media, preview, hidden details, bottom scroll, and Skills.
- Modify `flutter/codexflow/test/session_groups_test.dart`: keep user-initiated filtering protected.
- Modify `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/PersistentStatusFormatter.kt`: preserve title/detail format and icon-friendly compact text.
- Modify `flutter/codexflow/android/app/src/test/kotlin/com/example/codexflow_flutter/monitor/PersistentStatusFormatterTest.kt`: assert expanded notification details remain useful.

## Task 1: Backend Media Model And Store Tests

**Files:**
- Modify: `internal/runtime/models.go`
- Create: `internal/httpapi/session_media.go`
- Create: `internal/httpapi/session_media_test.go`

- [ ] **Step 1: Add the runtime media type**

Add this type next to `TurnItem` in `internal/runtime/models.go`:

```go
type ChatMediaAttachment struct {
	ID       string `json:"id"`
	Kind     string `json:"kind"`
	Name     string `json:"name"`
	MIMEType string `json:"mimeType"`
	URL      string `json:"url"`
	Size     int64  `json:"size"`
	Width    int    `json:"width,omitempty"`
	Height   int    `json:"height,omitempty"`
}
```

Then add this field to `TurnItem`:

```go
Media []ChatMediaAttachment `json:"media"`
```

- [ ] **Step 2: Write the failing media store test**

Create `internal/httpapi/session_media_test.go` with:

```go
package httpapi

import (
	"os"
	"path/filepath"
	"testing"
)

func TestSessionMediaStorePersistsAndReloadsAttachment(t *testing.T) {
	baseDir := t.TempDir()
	store, err := newSessionMediaStore(baseDir)
	if err != nil {
		t.Fatalf("newSessionMediaStore() error = %v", err)
	}

	source := filepath.Join(baseDir, "draft.png")
	if err := os.WriteFile(source, []byte("png bytes"), 0o600); err != nil {
		t.Fatalf("write source: %v", err)
	}

	attachment, err := store.AttachUpload(sessionMediaUpload{
		SessionID: "session-1",
		TurnID:   "turn-1",
		ItemID:   "item-1",
		Name:     "screen.png",
		MIMEType: "image/png",
		Size:     9,
		Path:     source,
	})
	if err != nil {
		t.Fatalf("AttachUpload() error = %v", err)
	}
	if attachment.URL != "/api/v1/sessions/session-1/media/"+attachment.ID {
		t.Fatalf("attachment URL = %q", attachment.URL)
	}

	reopened, err := newSessionMediaStore(baseDir)
	if err != nil {
		t.Fatalf("reopen newSessionMediaStore() error = %v", err)
	}
	media := reopened.MediaForItem("session-1", "turn-1", "item-1")
	if len(media) != 1 {
		t.Fatalf("MediaForItem() count = %d, want 1", len(media))
	}
	if media[0].Name != "screen.png" || media[0].MIMEType != "image/png" {
		t.Fatalf("media = %+v", media[0])
	}
}

func TestSessionMediaStoreRejectsPathTraversal(t *testing.T) {
	store, err := newSessionMediaStore(t.TempDir())
	if err != nil {
		t.Fatalf("newSessionMediaStore() error = %v", err)
	}

	if _, err := store.OpenMedia("session-1", "../outside"); err == nil {
		t.Fatalf("OpenMedia() error = nil, want path traversal rejection")
	}
}
```

- [ ] **Step 3: Run the failing test**

Run:

```bash
go test ./internal/httpapi -run 'TestSessionMediaStore'
```

Expected: fail because `newSessionMediaStore`, `sessionMediaUpload`, `AttachUpload`, `MediaForItem`, and `OpenMedia` do not exist yet.

- [ ] **Step 4: Implement the persistent media store**

Create `internal/httpapi/session_media.go` with these concrete responsibilities:

```go
package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/google/uuid"

	"codexflow/internal/runtime"
)

type sessionMediaUpload struct {
	SessionID string
	TurnID   string
	ItemID   string
	Name     string
	MIMEType string
	Size     int64
	Path     string
}

type sessionMediaRecord struct {
	SessionID  string                      `json:"sessionId"`
	TurnID    string                      `json:"turnId"`
	ItemID    string                      `json:"itemId"`
	FileName  string                      `json:"fileName"`
	Media     runtime.ChatMediaAttachment `json:"media"`
}

type sessionMediaStore struct {
	mu       sync.Mutex
	baseDir  string
	manifest string
	records  []sessionMediaRecord
}
```

Implement `newSessionMediaStore`, `AttachUpload`, `MediaForItem`, `OpenMedia`, `loadLocked`, `saveLocked`, and helper functions. Use:

```go
func sessionMediaURL(sessionID, mediaID string) string {
	return "/api/v1/sessions/" + sessionID + "/media/" + mediaID
}
```

The destination path must be:

```text
<baseDir>/<sessionID>/<mediaID><normalized extension>
```

Use `filepath.Clean`, reject empty `sessionID`/`mediaID`, and reject any `mediaID` containing `/`, `\`, or `..`. Save the manifest at:

```text
<baseDir>/manifest.json
```

- [ ] **Step 5: Run backend media store tests**

Run:

```bash
go test ./internal/httpapi -run 'TestSessionMediaStore'
```

Expected: pass.

## Task 2: Backend Media API Integration

**Files:**
- Modify: `internal/config/config.go`
- Modify: `cmd/codexflow-agent/main.go`
- Modify: `internal/httpapi/server.go`
- Modify: `internal/httpapi/image_uploads.go`
- Modify: `internal/runtime/transform.go`
- Modify: `internal/runtime/session_detail_pagination_test.go`

- [ ] **Step 1: Write the failing runtime media normalization test**

Add this test to `internal/runtime/session_detail_pagination_test.go`:

```go
func TestSessionDetailPreservesStructuredItemMedia(t *testing.T) {
	record := store.SessionRecord{
		Thread: codex.Thread{
			ID:            "thread-media",
			ModelProvider: "OpenAI",
			CWD:           "/tmp/media",
			Status:        codex.ThreadStatus{Type: "idle"},
			Turns: []codex.Turn{
				{
					ID:     "turn-media",
					Status: "completed",
					Items: []map[string]any{
						{
							"id":   "agent-media",
							"type": "agentMessage",
							"text": "done",
							"media": []any{
								map[string]any{
									"id":       "media-1",
									"kind":     "image",
									"name":     "result.png",
									"mimeType": "image/png",
									"url":      "/api/v1/sessions/thread-media/media/media-1",
									"size":     float64(10),
								},
							},
						},
					},
				},
			},
		},
	}

	detail := toSessionDetail(record, 0)
	media := detail.Turns[0].Items[0].Media
	if len(media) != 1 {
		t.Fatalf("media count = %d, want 1", len(media))
	}
	if got, want := media[0].Name, "result.png"; got != want {
		t.Fatalf("media name = %q, want %q", got, want)
	}
}
```

- [ ] **Step 2: Run the failing runtime test**

Run:

```bash
go test ./internal/runtime -run TestSessionDetailPreservesStructuredItemMedia
```

Expected: fail because `TurnItem.Media` is not populated by `normalizeItem`.

- [ ] **Step 3: Preserve structured media in `normalizeItem`**

In `internal/runtime/transform.go`, after the item type switch and before the empty-body fallback, parse `item["media"]` into `result.Media`.

Use a helper with these exact rules:

```go
func normalizeItemMedia(value any) []ChatMediaAttachment {
	raw, ok := value.([]any)
	if !ok {
		return nil
	}
	media := make([]ChatMediaAttachment, 0, len(raw))
	for _, entry := range raw {
		object, ok := entry.(map[string]any)
		if !ok {
			continue
		}
		attachment := ChatMediaAttachment{
			ID:       strings.TrimSpace(stringFieldAny(object, "id")),
			Kind:     strings.TrimSpace(stringFieldAny(object, "kind")),
			Name:     strings.TrimSpace(stringFieldAny(object, "name")),
			MIMEType: strings.TrimSpace(stringFieldAny(object, "mimeType")),
			URL:      strings.TrimSpace(stringFieldAny(object, "url")),
			Size:     int64(numberFieldAny(object, "size")),
			Width:    numberFieldAny(object, "width"),
			Height:   numberFieldAny(object, "height"),
		}
		if attachment.ID == "" || attachment.Kind == "" || attachment.URL == "" {
			continue
		}
		media = append(media, attachment)
	}
	return media
}
```

Also add `numberFieldAny` in the same file.

- [ ] **Step 4: Add media directory config**

In `internal/config/config.go`, add:

```go
MediaDir string
```

to `Config`, set it in `Load()`:

```go
MediaDir: getenv("CODEXFLOW_MEDIA_DIR", defaultMediaDir()),
```

and add:

```go
func defaultMediaDir() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "./codexflow-media"
	}
	return filepath.Join(home, ".codexflow", "media")
}
```

- [ ] **Step 5: Pass media config to HTTP server**

Change `cmd/codexflow-agent/main.go`:

```go
Handler: httpapi.NewServer(agent, logger, cfg).Handler(),
```

Change `internal/httpapi/server.go`:

```go
func NewServer(agent *runtime.Agent, logger *slog.Logger, cfg config.Config) *Server
```

Add `media *sessionMediaStore` to `Server`. If `newSessionMediaStore(cfg.MediaDir)` fails, log the error and use `newSessionMediaStore(filepath.Join(os.TempDir(), "codexflow", "media"))` so the server still starts with degraded persistence.

- [ ] **Step 6: Attach uploaded images to returned user message items**

Change `buildTurnInput` to return a struct:

```go
type turnInputBuildResult struct {
	Inputs  []map[string]any
	Uploads []resolvedImageUpload
}

type resolvedImageUpload struct {
	ID       string
	Name     string
	Path     string
	Size     int64
	MIMEType string
}
```

Update `imageUploadStore.Resolve` to return `imageUpload` instead of only a path. In `buildTurnInput`, append `resolvedImageUpload` for each image input and keep sending this to Codex:

```go
result.Inputs = append(result.Inputs, map[string]any{
	"type": "localImage",
	"path": item.Path,
})
```

After `StartTurn`, find the first `userMessage` item id in the returned `runtime.TurnDetail`, call `AttachUpload` for each resolved upload, and set `turn.Items[index].Media = mediaStore.MediaForItem(sessionID, turn.ID, item.ID)`.

After `SteerTurn`, fetch the latest session detail page with `TurnLimit: 1`, find the latest `userMessage` in the target turn, attach the uploads there, and return `{"ok": true}` as before.

- [ ] **Step 7: Serve session-scoped media URLs**

In `handleSessionByID`, add a route branch before other actions:

```go
if len(parts) == 3 && parts[1] == "media" {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	s.handleSessionMedia(w, r, sessionID, parts[2])
	return
}
```

Implement `handleSessionMedia` using `s.media.OpenMedia(sessionID, mediaID)`. Set `Content-Type` from stored MIME type or `mime.TypeByExtension`, then call `http.ServeContent`.

- [ ] **Step 8: Overlay media onto session detail responses**

Before writing a session detail response in `handleSessionByID`, call:

```go
s.overlaySessionMedia(&detail)
```

Implement:

```go
func (s *Server) overlaySessionMedia(detail *runtime.SessionDetail) {
	for turnIndex := range detail.Turns {
		turn := &detail.Turns[turnIndex]
		for itemIndex := range turn.Items {
			item := &turn.Items[itemIndex]
			persisted := s.media.MediaForItem(detail.Summary.ID, turn.ID, item.ID)
			if len(persisted) == 0 {
				continue
			}
			item.Media = append(item.Media, persisted...)
		}
	}
}
```

- [ ] **Step 9: Run backend tests**

Run:

```bash
go test ./internal/httpapi ./internal/runtime ./internal/config
```

Expected: pass.

## Task 3: Flutter Media Model And Parsing

**Files:**
- Modify: `flutter/codexflow/lib/models/app_models.dart`
- Modify: `flutter/codexflow/test/session_detail_pagination_model_test.dart`

- [ ] **Step 1: Write the failing Dart model test**

Add this test to `flutter/codexflow/test/session_detail_pagination_model_test.dart`:

```dart
test('parses media attachments on turn items', () {
  final detail = SessionDetail.fromJson(<String, dynamic>{
    'summary': _summaryJson(),
    'turns': <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'turn-media',
        'status': 'completed',
        'startedAt': 1,
        'completedAt': 2,
        'durationMs': 1000,
        'error': '',
        'diff': '',
        'planExplanation': '',
        'plan': <Map<String, dynamic>>[],
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'user-media',
            'type': 'userMessage',
            'body': 'screenshot attached',
            'media': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'media-1',
                'kind': 'image',
                'name': 'screen.png',
                'mimeType': 'image/png',
                'url': '/api/v1/sessions/session-paged/media/media-1',
                'size': 100,
                'width': 640,
                'height': 360,
              },
            ],
          },
        ],
      },
    ],
    'page': <String, dynamic>{
      'turnOffset': 0,
      'turnLimit': 1,
      'totalTurns': 1,
      'hasMoreBefore': false,
    },
  });

  final media = detail.turns.single.items.single.media;
  expect(media, hasLength(1));
  expect(media.single.name, 'screen.png');
  expect(media.single.url, '/api/v1/sessions/session-paged/media/media-1');
  expect(media.single.width, 640);
});
```

- [ ] **Step 2: Run the failing Flutter model test**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_detail_pagination_model_test.dart
```

Expected: fail because `TurnItem.media` and `ChatMediaAttachment` do not exist yet.

- [ ] **Step 3: Implement Dart media parsing**

In `flutter/codexflow/lib/models/app_models.dart`, add:

```dart
class ChatMediaAttachment {
  ChatMediaAttachment({
    required this.id,
    required this.kind,
    required this.name,
    required this.mimeType,
    required this.url,
    required this.size,
    required this.width,
    required this.height,
  });

  final String id;
  final String kind;
  final String name;
  final String mimeType;
  final String url;
  final int size;
  final int width;
  final int height;

  bool get isImage => kind == 'image' || mimeType.startsWith('image/');

  factory ChatMediaAttachment.fromJson(Map<String, dynamic> json) {
    return ChatMediaAttachment(
      id: asString(json['id']),
      kind: asString(json['kind']),
      name: asString(json['name']),
      mimeType: asString(json['mimeType']),
      url: asString(json['url']),
      size: asInt(json['size']),
      width: asInt(json['width']),
      height: asInt(json['height']),
    );
  }
}
```

Add `required this.media` and `final List<ChatMediaAttachment> media;` to `TurnItem`. Parse it in `TurnItem.fromJson`:

```dart
media: asList(json['media'])
    .map((item) => ChatMediaAttachment.fromJson(asMap(item)))
    .where((item) => item.id.isNotEmpty && item.url.isNotEmpty)
    .toList(),
```

- [ ] **Step 4: Update existing test fixtures**

Every direct `TurnItem(...)` constructor call in `flutter/codexflow/test/session_detail_screen_test.dart` must add:

```dart
media: const <ChatMediaAttachment>[],
```

- [ ] **Step 5: Run model tests**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_detail_pagination_model_test.dart test/session_groups_test.dart
```

Expected: pass.

## Task 4: Inline Media Rendering In Chat Timeline

**Files:**
- Modify: `flutter/codexflow/lib/screens/session_detail_screen.dart`
- Modify: `flutter/codexflow/test/session_detail_screen_test.dart`

- [ ] **Step 1: Write the failing inline media widget test**

Add this test to `flutter/codexflow/test/session_detail_screen_test.dart`:

```dart
testWidgets('session detail renders message media thumbnails and opens preview', (
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final prefs = await SharedPreferences.getInstance();
  final model = _StaticAppModel(prefs);
  final summary = _sessionSummary();
  model.dashboard = _dashboard(summary);
  model.sessionDetails[summary.id] = SessionDetail(
    summary: summary,
    turns: <TurnDetail>[_turnWithMedia()],
  );

  await tester.pumpWidget(
    ChangeNotifierProvider<AppModel>.value(
      value: model,
      child: MaterialApp(home: SessionDetailScreen(sessionId: summary.id)),
    ),
  );
  for (var index = 0; index < 6; index += 1) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  expect(find.byKey(const ValueKey<String>('chat-media-media-1')), findsOneWidget);

  await tester.tap(find.byKey(const ValueKey<String>('chat-media-media-1')));
  await tester.pumpAndSettle();

  expect(find.byKey(const ValueKey<String>('chat-media-preview-media-1')), findsOneWidget);
});
```

Add this helper near `_turnWithExecutionDetails()`:

```dart
TurnDetail _turnWithMedia() {
  return TurnDetail(
    id: 'turn-media',
    status: 'completed',
    startedAt: 1777610500,
    completedAt: 1777610510,
    durationMs: 10000,
    error: '',
    diff: '',
    planExplanation: '',
    plan: const <PlanStep>[],
    items: <TurnItem>[
      TurnItem(
        id: 'user-media',
        type: 'userMessage',
        title: '',
        body: 'attached screenshot',
        status: '',
        auxiliary: '',
        metadata: const <String, String>{},
        media: <ChatMediaAttachment>[
          ChatMediaAttachment(
            id: 'media-1',
            kind: 'image',
            name: 'screen.png',
            mimeType: 'image/png',
            url: '/api/v1/sessions/session-scroll-test/media/media-1',
            size: 100,
            width: 640,
            height: 360,
          ),
        ],
      ),
    ],
  );
}
```

- [ ] **Step 2: Run the failing widget test**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_detail_screen_test.dart -r expanded
```

Expected: fail because media thumbnails are not rendered.

- [ ] **Step 3: Add media rendering widgets**

In `session_detail_screen.dart`, pass `item.media` into `_ChatBubble`. Add a `_ChatMediaStrip` widget that:

- filters `media.where((item) => item.isImage)`
- renders each thumbnail with `Image.network`
- uses `ValueKey('chat-media-${media.id}')`
- constrains each thumbnail to max width `220`, max height `160`
- uses `AspectRatio` when width/height are present
- opens a `Dialog` containing `InteractiveViewer` and `Image.network`
- uses `ValueKey('chat-media-preview-${media.id}')` in the preview

Use the existing API base URL by reading `context.read<AppModel>().baseUrlString` and resolving relative media URLs:

```dart
Uri resolveMediaUri(String baseUrl, String url) {
  final parsed = Uri.tryParse(url);
  if (parsed != null && parsed.hasScheme) {
    return parsed;
  }
  return Uri.parse(baseUrl).resolve(url);
}
```

- [ ] **Step 4: Keep chat details hidden**

Do not add reasoning, command execution, file changes, plans, diffs, or approval blocks back into `_timelineChildren`. `_isConversationItem` must remain:

```dart
return item.type == 'userMessage' || item.type == 'agentMessage';
```

- [ ] **Step 5: Run chat timeline tests**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_detail_screen_test.dart -r expanded
```

Expected: pass.

## Task 5: Status-First Home And Compact Session Browser

**Files:**
- Modify: `flutter/codexflow/lib/screens/dashboard_screen.dart`
- Modify: `flutter/codexflow/lib/domain/session_groups.dart`
- Modify: `flutter/codexflow/lib/widgets/common.dart`
- Modify: `flutter/codexflow/lib/theme/palette.dart`
- Modify: `flutter/codexflow/test/session_groups_test.dart`

- [ ] **Step 1: Protect user-initiated filtering**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_groups_test.dart
```

Expected: pass. The existing test `hides agent-initiated sessions from visible session groups` must remain green.

- [ ] **Step 2: Remove decorative orb background**

In `flutter/codexflow/lib/widgets/common.dart`, simplify `AtmosphereBackground` to a restrained banded light background:

```dart
class AtmosphereBackground extends StatelessWidget {
  const AtmosphereBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(gradient: Palette.dashboardGradient),
    );
  }
}
```

Delete `_BlurCircle` because the approved UI direction avoids orb decoration.

- [ ] **Step 3: Tighten secondary text contrast**

In `flutter/codexflow/lib/theme/palette.dart`, set:

```dart
static const mutedInk = Color.fromRGBO(77, 86, 92, 1);
static const shell = Color.fromRGBO(238, 240, 236, 1);
static const line = Color.fromRGBO(0, 0, 0, 0.10);
```

Do not change `canvas`, `ink`, or the main accent colors in this task.

- [ ] **Step 4: Refactor home into status strip plus three entries**

In `DashboardScreen.build`, keep `groupSessionsForAgent` as the source of counts. Replace the top row/card stack with:

- `_AgentStatusStrip`
- `_HomeMetricButton` for total sessions
- `_HomeMetricButton` for loaded sessions
- `_HomeMetricButton` for running sessions

The status strip should show online/offline, host, running count, pending count, and last refresh. Use `model.dashboard.agent.listenAddr` for host and `DateTime.now()` display during refresh if no server timestamp exists.

- [ ] **Step 5: Compact Session Browser rows**

In `SessionRow`, reduce vertical padding and keep only:

- title
- full cwd
- updated time
- status pill
- preview when non-empty
- horizontal tags for loaded/source/branch/pending

Keep `_sortedSessions` as newest-first and `_matchesQuery` as the search source. Do not reintroduce a top-level session list on the home screen.

- [ ] **Step 6: Run Flutter analyzer for UI files**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter analyze
```

Expected: no new analyzer errors from edited Flutter files.

## Task 6: Composer, Skills, And Notification Polish

**Files:**
- Modify: `flutter/codexflow/lib/screens/session_detail_screen.dart`
- Modify: `flutter/codexflow/lib/state/app_model.dart`
- Modify: `flutter/codexflow/android/app/src/main/kotlin/com/example/codexflow_flutter/monitor/PersistentStatusFormatter.kt`
- Modify: `flutter/codexflow/android/app/src/test/kotlin/com/example/codexflow_flutter/monitor/PersistentStatusFormatterTest.kt`

- [ ] **Step 1: Keep Skills refresh behavior explicit**

Confirm `AppModel.refreshDashboard({bool refreshSkills = true})` still refreshes Skills by default and `SessionDetailScreen.initState` calls:

```dart
unawaited(_refreshSessionPage(refreshSkills: true));
```

If an implementation changed either behavior, restore it.

- [ ] **Step 2: Keep Skills sheet command-palette behavior tested**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test test/session_detail_screen_test.dart --plain-name 'skills sheet sorts, searches, and inserts selected skill'
```

Expected: pass.

- [ ] **Step 3: Compress composer vertical height**

In `_ComposerCard`, keep Skills and add-image controls in one row with the stop/end affordance. Keep selected image thumbnails horizontal and cap their height at `44`. Keep the text input `minLines: 1` and `maxLines: 4`.

Do not add helper text explaining shortcuts or features inside the composer.

- [ ] **Step 4: Preserve notification icon/action resources**

Confirm these files exist:

```text
flutter/codexflow/android/app/src/main/res/drawable/ic_dashboard_24.xml
flutter/codexflow/android/app/src/main/res/drawable/ic_approvals_24.xml
flutter/codexflow/android/app/src/main/res/drawable/ic_refresh_24.xml
```

If any is missing, recreate it as a white vector drawable with a `24dp` viewport and use it in `CodexFlowNotifications.persistent()`.

- [ ] **Step 5: Keep expanded notification details useful**

Update or preserve `PersistentStatusFormatterTest` assertions so the expanded text contains:

```text
Agent:
Host:
Managed sessions:
Running turns:
Pending manual actions:
Running sessions:
Last checked:
```

Run:

```bash
cd flutter/codexflow/android
./gradlew testDebugUnitTest --tests '*PersistentStatusFormatterTest'
```

Expected: pass.

## Task 7: Full Verification And APK Build

**Files:**
- Verify all changed Go, Flutter, and Android files.
- Publish APK only after tests pass.

- [ ] **Step 1: Format Go files**

Run:

```bash
gofmt -w internal/config/config.go internal/httpapi/image_uploads.go internal/httpapi/server.go internal/httpapi/session_media.go internal/httpapi/session_media_test.go internal/runtime/models.go internal/runtime/transform.go internal/runtime/session_detail_pagination_test.go cmd/codexflow-agent/main.go
```

Expected: command exits 0.

- [ ] **Step 2: Run Go tests**

Run:

```bash
go test ./...
```

Expected: pass.

- [ ] **Step 3: Format Dart files**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/dart format lib test
```

Expected: command exits 0 and only intended Flutter files are formatted.

- [ ] **Step 4: Run Flutter tests**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter test
```

Expected: pass.

- [ ] **Step 5: Run Flutter analyzer**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter analyze
```

Expected: no issues.

- [ ] **Step 6: Run Android unit tests**

Run:

```bash
cd flutter/codexflow/android
./gradlew testDebugUnitTest
```

Expected: pass.

- [ ] **Step 7: Build release APK**

Run:

```bash
cd flutter/codexflow
/home/lin/.local/share/flutter/bin/flutter build apk --release
```

Expected: release APK is produced under:

```text
flutter/codexflow/build/app/outputs/flutter-apk/app-release.apk
```

- [ ] **Step 8: Publish local APK artifact**

Run:

```bash
install -D -m 0644 flutter/codexflow/build/app/outputs/flutter-apk/app-release.apk /home/lin/.local/share/codexflow-web/web/codexflow-android-latest.apk
```

Expected: phone can download the latest APK from the local CodexFlow web server.

## Self-Review

- Spec coverage: Session Overview Home, Session Browser, Chat Timeline, Composer/Skills, Chat Media Attachments, and Expanded Persistent Status Notification all map to tasks above.
- Risk coverage: persistent media storage, session-scoped serving, local path safety, visible timeline paging, user-initiated session filtering, and Android notification formatting all have explicit tests or verification commands.
- Placeholder scan: this plan contains no unfinished marker steps. Each task names exact files and expected commands.
- Type consistency: Go uses `runtime.ChatMediaAttachment`; Dart uses `ChatMediaAttachment`; both expose `id`, `kind`, `name`, `mimeType`, `url`, `size`, `width`, and `height`.
