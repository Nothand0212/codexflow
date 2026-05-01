package httpapi

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"

	"codexflow/internal/runtime"
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
		TurnID:    "turn-1",
		ItemID:    "item-1",
		Name:      "screen.png",
		MIMEType:  "image/png",
		Size:      9,
		Path:      source,
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

func TestSessionMediaStoreRejectsManifestFileNameTraversal(t *testing.T) {
	baseDir := t.TempDir()
	outsidePath := filepath.Join(filepath.Dir(baseDir), "outside.png")
	if err := os.WriteFile(outsidePath, []byte("outside"), 0o600); err != nil {
		t.Fatalf("write outside file: %v", err)
	}

	manifest := []sessionMediaRecord{
		{
			SessionID: "session-1",
			TurnID:    "turn-1",
			ItemID:    "item-1",
			FileName:  "../../outside.png",
			Media: runtime.ChatMediaAttachment{
				ID:       "media-1",
				Kind:     "image",
				Name:     "outside.png",
				MIMEType: "image/png",
				URL:      "/api/v1/sessions/session-1/media/media-1",
				Size:     7,
			},
		},
	}
	payload, err := json.Marshal(manifest)
	if err != nil {
		t.Fatalf("marshal manifest: %v", err)
	}
	if err := os.WriteFile(filepath.Join(baseDir, "manifest.json"), payload, 0o600); err != nil {
		t.Fatalf("write manifest: %v", err)
	}

	store, err := newSessionMediaStore(baseDir)
	if err != nil {
		t.Fatalf("newSessionMediaStore() error = %v", err)
	}
	if media, err := store.OpenMedia("session-1", "media-1"); err == nil {
		_ = media.File.Close()
		t.Fatalf("OpenMedia() error = nil, want manifest path traversal rejection")
	}
}
