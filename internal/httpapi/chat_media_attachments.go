package httpapi

import (
	"context"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"codexflow/internal/runtime"
)

type chatMediaAttachmentModule struct {
	uploads *imageUploadStore
	store   *sessionMediaStore
}

type chatTurnInput struct {
	Type     string `json:"type"`
	Text     string `json:"text"`
	UploadID string `json:"uploadId"`
}

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

type sessionDetailPager interface {
	SessionDetailPage(context.Context, string, runtime.SessionDetailPageRequest) (runtime.SessionDetail, error)
}

func newChatMediaAttachmentModule(uploads *imageUploadStore, store *sessionMediaStore) *chatMediaAttachmentModule {
	if uploads == nil {
		uploads = newImageUploadStore()
	}
	return &chatMediaAttachmentModule{
		uploads: uploads,
		store:   store,
	}
}

func (m *chatMediaAttachmentModule) SaveTemporaryImageUpload(name string, payload []byte) (imageUpload, error) {
	return m.uploads.Save(name, payload)
}

func (m *chatMediaAttachmentModule) OpenSessionMedia(sessionID, mediaID string) (sessionMediaFile, error) {
	if m == nil || m.store == nil {
		return sessionMediaFile{}, fmt.Errorf("media not found")
	}
	return m.store.OpenMedia(sessionID, mediaID)
}

func (m *chatMediaAttachmentModule) BuildTurnInput(
	legacyPrompt string,
	inputs []chatTurnInput,
) (turnInputBuildResult, error) {
	if len(inputs) == 0 {
		prompt := strings.TrimSpace(legacyPrompt)
		if prompt == "" {
			return turnInputBuildResult{}, fmt.Errorf("prompt or inputs is required")
		}
		return turnInputBuildResult{Inputs: []map[string]any{composeTextInput(prompt)}}, nil
	}

	result := turnInputBuildResult{
		Inputs:  make([]map[string]any, 0, len(inputs)),
		Uploads: make([]resolvedImageUpload, 0),
	}
	for _, input := range inputs {
		switch strings.TrimSpace(input.Type) {
		case "text":
			text := strings.TrimSpace(input.Text)
			if text == "" {
				return turnInputBuildResult{}, fmt.Errorf("text input cannot be empty")
			}
			result.Inputs = append(result.Inputs, composeTextInput(text))
		case "image":
			upload, err := m.uploads.Resolve(input.UploadID)
			if err != nil {
				return turnInputBuildResult{}, err
			}
			result.Inputs = append(result.Inputs, map[string]any{
				"type": "localImage",
				"path": upload.Path,
			})
			result.Uploads = append(result.Uploads, resolvedImageUpload{
				ID:       upload.ID,
				Name:     upload.Name,
				Path:     upload.Path,
				Size:     upload.Size,
				MIMEType: detectUploadMIMEType(upload),
			})
		default:
			return turnInputBuildResult{}, fmt.Errorf("unsupported input type %q", input.Type)
		}
	}
	return result, nil
}

func (m *chatMediaAttachmentModule) AttachUploadsToFirstUserMessage(sessionID string, turn *runtime.TurnDetail, uploads []resolvedImageUpload) error {
	if m == nil || m.store == nil || turn == nil || len(uploads) == 0 {
		return nil
	}
	for index := range turn.Items {
		if turn.Items[index].Type != "userMessage" {
			continue
		}
		if err := m.attachUploadsToItem(sessionID, turn.ID, turn.Items[index].ID, uploads); err != nil {
			return err
		}
		turn.Items[index].Media = m.store.MediaForItem(sessionID, turn.ID, turn.Items[index].ID)
		return nil
	}
	return nil
}

func (m *chatMediaAttachmentModule) AttachSteerUploads(
	ctx context.Context,
	pager sessionDetailPager,
	sessionID string,
	turnID string,
	uploads []resolvedImageUpload,
) error {
	if m == nil || m.store == nil || len(uploads) == 0 {
		return nil
	}
	detail, err := pager.SessionDetailPage(ctx, sessionID, runtime.SessionDetailPageRequest{TurnLimit: runtime.MaxSessionDetailTurnLimit})
	if err != nil {
		return err
	}
	targetTurnID := strings.TrimSpace(turnID)
	for turnIndex := len(detail.Turns) - 1; turnIndex >= 0; turnIndex-- {
		turn := detail.Turns[turnIndex]
		if targetTurnID != "" && turn.ID != targetTurnID {
			continue
		}
		if itemID, ok := latestUserMessageItemID(turn); ok {
			return m.attachUploadsToItem(sessionID, turn.ID, itemID, uploads)
		}
		return fmt.Errorf("turn %q has no user message for image attachment", turn.ID)
	}
	if targetTurnID != "" {
		return fmt.Errorf("turn %q could not be found for image attachment", targetTurnID)
	}
	return nil
}

func (m *chatMediaAttachmentModule) OverlaySessionMedia(detail *runtime.SessionDetail) {
	if m == nil || m.store == nil || detail == nil {
		return
	}
	sessionID := detail.Summary.ID
	for turnIndex := range detail.Turns {
		turn := &detail.Turns[turnIndex]
		for itemIndex := range turn.Items {
			item := &turn.Items[itemIndex]
			item.Media = m.persistStructuredItemMedia(sessionID, turn.ID, item.ID, item.Media)
			for _, media := range m.store.MediaForItem(sessionID, turn.ID, item.ID) {
				if hasMediaAttachment(item.Media, media) {
					continue
				}
				item.Media = append(item.Media, media)
			}
		}
	}
}

func (m *chatMediaAttachmentModule) persistStructuredItemMedia(
	sessionID string,
	turnID string,
	itemID string,
	media []runtime.ChatMediaAttachment,
) []runtime.ChatMediaAttachment {
	if len(media) == 0 {
		return media
	}

	result := make([]runtime.ChatMediaAttachment, 0, len(media))
	for _, item := range media {
		sourcePath, sourceURL, ok := localStructuredMediaSource(item.URL)
		if !ok {
			result = append(result, item)
			continue
		}

		existing := m.store.MediaForSource(sessionID, turnID, itemID, sourceURL)
		if len(existing) > 0 {
			result = append(result, existing...)
			continue
		}

		size := item.Size
		if size <= 0 {
			if stat, err := os.Stat(sourcePath); err == nil {
				size = stat.Size()
			}
		}
		name := item.Name
		if strings.TrimSpace(name) == "" {
			name = filepath.Base(sourcePath)
		}
		attachment, err := m.store.AttachUpload(sessionMediaUpload{
			SessionID: sessionID,
			TurnID:    turnID,
			ItemID:    itemID,
			Name:      name,
			MIMEType:  item.MIMEType,
			Path:      sourcePath,
			Size:      size,
			Width:     item.Width,
			Height:    item.Height,
			SourceURL: sourceURL,
		})
		if err != nil {
			result = append(result, item)
			continue
		}
		result = append(result, attachment)
	}
	return result
}

func (m *chatMediaAttachmentModule) attachUploadsToItem(sessionID, turnID, itemID string, uploads []resolvedImageUpload) error {
	for _, upload := range uploads {
		if _, err := m.store.AttachUpload(sessionMediaUpload{
			SessionID: sessionID,
			TurnID:    turnID,
			ItemID:    itemID,
			Name:      upload.Name,
			MIMEType:  upload.MIMEType,
			Path:      upload.Path,
			Size:      upload.Size,
		}); err != nil {
			return err
		}
	}
	return nil
}

func detectUploadMIMEType(upload imageUpload) string {
	if file, err := os.Open(upload.Path); err == nil {
		defer file.Close()
		buffer := make([]byte, 512)
		n, readErr := file.Read(buffer)
		if (readErr == nil || readErr == io.EOF) && n > 0 {
			if contentType := http.DetectContentType(buffer[:n]); strings.HasPrefix(contentType, "image/") {
				return contentType
			}
		}
	}

	for _, path := range []string{upload.Name, upload.Path} {
		if contentType := mime.TypeByExtension(filepath.Ext(strings.TrimSpace(path))); contentType != "" {
			return contentType
		}
	}
	return ""
}

func latestUserMessageItemID(turn runtime.TurnDetail) (string, bool) {
	for index := len(turn.Items) - 1; index >= 0; index-- {
		if turn.Items[index].Type == "userMessage" {
			return turn.Items[index].ID, true
		}
	}
	return "", false
}

func hasMediaAttachment(existing []runtime.ChatMediaAttachment, candidate runtime.ChatMediaAttachment) bool {
	for _, media := range existing {
		if candidate.ID != "" && media.ID == candidate.ID {
			return true
		}
		if candidate.URL != "" && media.URL == candidate.URL {
			return true
		}
	}
	return false
}

func localStructuredMediaSource(rawURL string) (string, string, bool) {
	rawURL = strings.TrimSpace(rawURL)
	if rawURL == "" || isManagedSessionMediaURL(rawURL) {
		return "", "", false
	}

	parsed, err := url.Parse(rawURL)
	if err == nil && parsed.Scheme != "" {
		if parsed.Scheme != "file" {
			return "", "", false
		}
		if parsed.Host != "" && parsed.Host != "localhost" {
			return "", "", false
		}
		path, err := url.PathUnescape(parsed.Path)
		if err != nil {
			return "", "", false
		}
		if path == "" || !filepath.IsAbs(path) {
			return "", "", false
		}
		return path, "file://" + path, true
	}

	if filepath.IsAbs(rawURL) {
		return rawURL, rawURL, true
	}
	return "", "", false
}

func isManagedSessionMediaURL(rawURL string) bool {
	return strings.HasPrefix(rawURL, "/api/v1/sessions/") &&
		strings.Contains(rawURL, "/media/")
}

func composeTextInput(prompt string) map[string]any {
	return map[string]any{
		"type":          "text",
		"text":          prompt,
		"text_elements": []any{},
	}
}
