package httpapi

import (
	"context"
	"os"
	"strings"
	"testing"

	"codexflow/internal/runtime"
)

func TestChatMediaAttachmentModuleBuildsLocalImageInput(t *testing.T) {
	module := newTestChatMediaAttachmentModule(t)
	upload := saveTestImageUpload(t, module, "screen.png")

	result, err := module.BuildTurnInput("", []chatTurnInput{
		{Type: "text", Text: "inspect this"},
		{Type: "image", UploadID: upload.ID},
	})
	if err != nil {
		t.Fatalf("BuildTurnInput() error = %v", err)
	}
	if len(result.Inputs) != 2 {
		t.Fatalf("Inputs count = %d, want 2", len(result.Inputs))
	}
	if got := result.Inputs[1]["type"]; got != "localImage" {
		t.Fatalf("image input type = %v, want localImage", got)
	}
	if got := result.Inputs[1]["path"]; got != upload.Path {
		t.Fatalf("image input path = %v, want %s", got, upload.Path)
	}
	if len(result.Uploads) != 1 {
		t.Fatalf("Uploads count = %d, want 1", len(result.Uploads))
	}
	if result.Uploads[0].MIMEType != "image/png" {
		t.Fatalf("upload MIME type = %q, want image/png", result.Uploads[0].MIMEType)
	}
}

func TestChatMediaAttachmentModulePersistsAndOverlaysWithoutDuplicates(t *testing.T) {
	module := newTestChatMediaAttachmentModule(t)
	upload := saveTestImageUpload(t, module, "screen.png")
	result, err := module.BuildTurnInput("", []chatTurnInput{{Type: "image", UploadID: upload.ID}})
	if err != nil {
		t.Fatalf("BuildTurnInput() error = %v", err)
	}

	turn := runtime.TurnDetail{
		ID: "turn-1",
		Items: []runtime.TurnItem{
			{ID: "agent-1", Type: "agentMessage", Body: "local path /tmp/screen.png"},
			{ID: "user-1", Type: "userMessage"},
		},
	}
	if err := module.AttachUploadsToFirstUserMessage("session-1", &turn, result.Uploads); err != nil {
		t.Fatalf("AttachUploadsToFirstUserMessage() error = %v", err)
	}
	if len(turn.Items[1].Media) != 1 {
		t.Fatalf("user media count = %d, want 1", len(turn.Items[1].Media))
	}
	attached := turn.Items[1].Media[0]

	detail := runtime.SessionDetail{
		Summary: runtime.SessionSummary{ID: "session-1"},
		Turns: []runtime.TurnDetail{
			{
				ID: "turn-1",
				Items: []runtime.TurnItem{
					{ID: "agent-1", Type: "agentMessage", Body: "local path /tmp/screen.png"},
					{ID: "user-1", Type: "userMessage", Media: []runtime.ChatMediaAttachment{attached}},
				},
			},
		},
	}
	module.OverlaySessionMedia(&detail)
	if len(detail.Turns[0].Items[0].Media) != 0 {
		t.Fatalf("agent local filesystem path became media: %+v", detail.Turns[0].Items[0].Media)
	}
	if len(detail.Turns[0].Items[1].Media) != 1 {
		t.Fatalf("overlay duplicated media, count = %d", len(detail.Turns[0].Items[1].Media))
	}
	if detail.Turns[0].Items[1].Media[0].ID != attached.ID {
		t.Fatalf("overlay media ID = %q, want %q", detail.Turns[0].Items[1].Media[0].ID, attached.ID)
	}
}

func TestChatMediaAttachmentModulePersistsStructuredLocalAgentMedia(t *testing.T) {
	module := newTestChatMediaAttachmentModule(t)
	sourcePath := t.TempDir() + "/agent-result.png"
	if err := os.WriteFile(sourcePath, []byte("\x89PNG\r\n\x1a\nagent image bytes"), 0o600); err != nil {
		t.Fatalf("write source image: %v", err)
	}
	sourceURL := "file://" + sourcePath

	detail := runtime.SessionDetail{
		Summary: runtime.SessionSummary{ID: "session-agent-media"},
		Turns: []runtime.TurnDetail{
			{
				ID: "turn-agent",
				Items: []runtime.TurnItem{
					{
						ID:   "agent-media",
						Type: "agentMessage",
						Media: []runtime.ChatMediaAttachment{
							{
								ID:       "upstream-media",
								Kind:     "image",
								Name:     "agent-result.png",
								MIMEType: "image/png",
								URL:      sourceURL,
								Size:     27,
								Width:    640,
								Height:   360,
							},
						},
					},
				},
			},
		},
	}

	module.OverlaySessionMedia(&detail)

	media := detail.Turns[0].Items[0].Media
	if len(media) != 1 {
		t.Fatalf("media count = %d, want 1", len(media))
	}
	if strings.HasPrefix(media[0].URL, "file://") {
		t.Fatalf("media URL = %q, want managed session media URL", media[0].URL)
	}
	if !strings.HasPrefix(media[0].URL, "/api/v1/sessions/session-agent-media/media/") {
		t.Fatalf("media URL = %q, want session-scoped media URL", media[0].URL)
	}
	if media[0].Width != 640 || media[0].Height != 360 {
		t.Fatalf("media dimensions = %dx%d, want 640x360", media[0].Width, media[0].Height)
	}

	freshDetail := runtime.SessionDetail{
		Summary: runtime.SessionSummary{ID: "session-agent-media"},
		Turns: []runtime.TurnDetail{
			{
				ID: "turn-agent",
				Items: []runtime.TurnItem{
					{
						ID:   "agent-media",
						Type: "agentMessage",
						Media: []runtime.ChatMediaAttachment{
							{
								ID:       "upstream-media",
								Kind:     "image",
								Name:     "agent-result.png",
								MIMEType: "image/png",
								URL:      sourceURL,
							},
						},
					},
				},
			},
		},
	}
	module.OverlaySessionMedia(&freshDetail)

	if got := module.store.MediaForItem("session-agent-media", "turn-agent", "agent-media"); len(got) != 1 {
		t.Fatalf("persisted media count after repeated overlay = %d, want 1", len(got))
	}
	if freshDetail.Turns[0].Items[0].Media[0].ID != media[0].ID {
		t.Fatalf("reused media ID = %q, want %q", freshDetail.Turns[0].Items[0].Media[0].ID, media[0].ID)
	}
}

func TestChatMediaAttachmentModuleAttachesSteerUploadsToLatestUserMessage(t *testing.T) {
	module := newTestChatMediaAttachmentModule(t)
	upload := saveTestImageUpload(t, module, "steer.png")
	result, err := module.BuildTurnInput("", []chatTurnInput{{Type: "image", UploadID: upload.ID}})
	if err != nil {
		t.Fatalf("BuildTurnInput() error = %v", err)
	}

	pager := fakeSessionDetailPager{
		detail: runtime.SessionDetail{
			Summary: runtime.SessionSummary{ID: "session-1"},
			Turns: []runtime.TurnDetail{
				{
					ID: "turn-1",
					Items: []runtime.TurnItem{
						{ID: "user-old", Type: "userMessage"},
						{ID: "agent-1", Type: "agentMessage"},
						{ID: "user-new", Type: "userMessage"},
					},
				},
			},
		},
	}

	if err := module.AttachSteerUploads(context.Background(), pager, "session-1", "turn-1", result.Uploads); err != nil {
		t.Fatalf("AttachSteerUploads() error = %v", err)
	}
	oldMedia := module.store.MediaForItem("session-1", "turn-1", "user-old")
	if len(oldMedia) != 0 {
		t.Fatalf("old user message media count = %d, want 0", len(oldMedia))
	}
	newMedia := module.store.MediaForItem("session-1", "turn-1", "user-new")
	if len(newMedia) != 1 {
		t.Fatalf("latest user message media count = %d, want 1", len(newMedia))
	}
}

func newTestChatMediaAttachmentModule(t *testing.T) *chatMediaAttachmentModule {
	t.Helper()
	store, err := newSessionMediaStore(t.TempDir())
	if err != nil {
		t.Fatalf("newSessionMediaStore() error = %v", err)
	}
	uploads := newImageUploadStore()
	uploads.baseDir = t.TempDir()
	return newChatMediaAttachmentModule(uploads, store)
}

func saveTestImageUpload(t *testing.T, module *chatMediaAttachmentModule, name string) imageUpload {
	t.Helper()
	upload, err := module.uploads.Save(name, []byte("\x89PNG\r\n\x1a\nimage bytes"))
	if err != nil {
		t.Fatalf("Save() error = %v", err)
	}
	return upload
}

type fakeSessionDetailPager struct {
	detail runtime.SessionDetail
	err    error
}

func (p fakeSessionDetailPager) SessionDetailPage(
	context.Context,
	string,
	runtime.SessionDetailPageRequest,
) (runtime.SessionDetail, error) {
	if p.err != nil {
		return runtime.SessionDetail{}, p.err
	}
	return p.detail, nil
}

func TestChatMediaAttachmentModuleRejectsLocalFilesystemPathAsInput(t *testing.T) {
	module := newTestChatMediaAttachmentModule(t)
	_, err := module.BuildTurnInput("", []chatTurnInput{{Type: "image", UploadID: "/tmp/screen.png"}})
	if err == nil {
		t.Fatal("BuildTurnInput() error = nil, want unknown upload ID rejection")
	}
	if !strings.Contains(err.Error(), "uploaded image not found") {
		t.Fatalf("BuildTurnInput() error = %q, want uploaded image lookup error", err)
	}
}
