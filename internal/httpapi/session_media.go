package httpapi

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"sync"

	"github.com/google/uuid"

	"codexflow/internal/runtime"
)

type sessionMediaUpload struct {
	SessionID string
	TurnID    string
	ItemID    string
	Name      string
	MIMEType  string
	Path      string
	Size      int64
}

type sessionMediaRecord struct {
	SessionID string                      `json:"sessionId"`
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

type sessionMediaFile struct {
	File  *os.File
	Media runtime.ChatMediaAttachment
}

func newSessionMediaStore(baseDir string) (*sessionMediaStore, error) {
	baseDir = strings.TrimSpace(baseDir)
	if baseDir == "" {
		return nil, errors.New("media base dir is required")
	}
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return nil, err
	}
	store := &sessionMediaStore{
		baseDir:  baseDir,
		manifest: filepath.Join(baseDir, "manifest.json"),
		records:  []sessionMediaRecord{},
	}
	store.mu.Lock()
	defer store.mu.Unlock()
	if err := store.loadLocked(); err != nil {
		return nil, err
	}
	return store, nil
}

func (s *sessionMediaStore) AttachUpload(upload sessionMediaUpload) (runtime.ChatMediaAttachment, error) {
	sessionID, err := cleanPathSegment(upload.SessionID, "session id")
	if err != nil {
		return runtime.ChatMediaAttachment{}, err
	}
	if strings.TrimSpace(upload.TurnID) == "" {
		return runtime.ChatMediaAttachment{}, errors.New("turn id is required")
	}
	if strings.TrimSpace(upload.ItemID) == "" {
		return runtime.ChatMediaAttachment{}, errors.New("item id is required")
	}
	if strings.TrimSpace(upload.Path) == "" {
		return runtime.ChatMediaAttachment{}, errors.New("upload path is required")
	}

	mediaID := uuid.NewString()
	ext := normalizeExt(filepath.Ext(sanitizeMediaName(upload.Name)))
	if ext == "" {
		ext = normalizeExt(filepath.Ext(upload.Path))
	}
	if ext == "" {
		ext = ".bin"
	}
	fileName := mediaID + ext
	sessionDir := filepath.Join(s.baseDir, sessionID)
	destination := filepath.Join(sessionDir, fileName)

	if err := os.MkdirAll(sessionDir, 0o755); err != nil {
		return runtime.ChatMediaAttachment{}, err
	}
	if err := copyFile(upload.Path, destination); err != nil {
		return runtime.ChatMediaAttachment{}, err
	}

	attachment := runtime.ChatMediaAttachment{
		ID:       mediaID,
		Kind:     mediaKind(upload.MIMEType),
		Name:     sanitizeMediaName(upload.Name),
		MIMEType: strings.TrimSpace(upload.MIMEType),
		URL:      fmt.Sprintf("/api/v1/sessions/%s/media/%s", sessionID, mediaID),
		Size:     upload.Size,
	}
	if attachment.Name == "" {
		attachment.Name = "upload" + ext
	}

	record := sessionMediaRecord{
		SessionID: sessionID,
		TurnID:    strings.TrimSpace(upload.TurnID),
		ItemID:    strings.TrimSpace(upload.ItemID),
		FileName:  fileName,
		Media:     attachment,
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	s.records = append(s.records, record)
	if err := s.saveLocked(); err != nil {
		s.records = s.records[:len(s.records)-1]
		_ = os.Remove(destination)
		return runtime.ChatMediaAttachment{}, err
	}
	return attachment, nil
}

func (s *sessionMediaStore) MediaForItem(sessionID, turnID, itemID string) []runtime.ChatMediaAttachment {
	sessionID = strings.TrimSpace(sessionID)
	turnID = strings.TrimSpace(turnID)
	itemID = strings.TrimSpace(itemID)

	s.mu.Lock()
	defer s.mu.Unlock()

	media := make([]runtime.ChatMediaAttachment, 0)
	for _, record := range s.records {
		if record.SessionID == sessionID && record.TurnID == turnID && record.ItemID == itemID {
			media = append(media, record.Media)
		}
	}
	return media
}

// OpenMedia opens a persisted media file for HTTP serving and returns the
// readable file with its attachment metadata. Callers own File and must close it.
func (s *sessionMediaStore) OpenMedia(sessionID, mediaID string) (sessionMediaFile, error) {
	sessionID, err := cleanPathSegment(sessionID, "session id")
	if err != nil {
		return sessionMediaFile{}, err
	}
	mediaID, err = cleanPathSegment(mediaID, "media id")
	if err != nil {
		return sessionMediaFile{}, err
	}

	s.mu.Lock()
	var record sessionMediaRecord
	found := false
	for _, candidate := range s.records {
		if candidate.SessionID == sessionID && candidate.Media.ID == mediaID {
			record = candidate
			found = true
			break
		}
	}
	s.mu.Unlock()
	if !found {
		return sessionMediaFile{}, errors.New("media not found")
	}

	path, err := s.mediaPath(sessionID, record.FileName)
	if err != nil {
		return sessionMediaFile{}, err
	}
	file, err := os.Open(path)
	if err != nil {
		return sessionMediaFile{}, err
	}
	return sessionMediaFile{File: file, Media: record.Media}, nil
}

func (s *sessionMediaStore) loadLocked() error {
	payload, err := os.ReadFile(s.manifest)
	if errors.Is(err, os.ErrNotExist) {
		s.records = []sessionMediaRecord{}
		return nil
	}
	if err != nil {
		return err
	}
	if len(strings.TrimSpace(string(payload))) == 0 {
		s.records = []sessionMediaRecord{}
		return nil
	}
	return json.Unmarshal(payload, &s.records)
}

func (s *sessionMediaStore) saveLocked() error {
	payload, err := json.MarshalIndent(s.records, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.manifest + ".tmp"
	if err := os.WriteFile(tmp, payload, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, s.manifest)
}

func cleanPathSegment(value, label string) (string, error) {
	value = strings.TrimSpace(value)
	if value == "" {
		return "", fmt.Errorf("%s is required", label)
	}
	if strings.Contains(value, "/") || strings.Contains(value, "\\") || strings.Contains(value, "..") {
		return "", fmt.Errorf("%s contains invalid path characters", label)
	}
	return value, nil
}

func (s *sessionMediaStore) mediaPath(sessionID, fileName string) (string, error) {
	fileName = strings.TrimSpace(fileName)
	if fileName == "" {
		return "", errors.New("media file name is required")
	}
	if filepath.Base(fileName) != fileName || strings.Contains(fileName, "/") || strings.Contains(fileName, "\\") {
		return "", errors.New("media file name contains invalid path characters")
	}

	sessionDir := filepath.Join(s.baseDir, sessionID)
	path := filepath.Join(sessionDir, fileName)
	relative, err := filepath.Rel(sessionDir, path)
	if err != nil {
		return "", err
	}
	if relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
		return "", errors.New("media path escapes session directory")
	}
	return path, nil
}

func sanitizeMediaName(name string) string {
	name = strings.TrimSpace(strings.ReplaceAll(name, "\\", "/"))
	if name == "" {
		return ""
	}
	name = filepath.Base(name)
	if name == "." || name == string(filepath.Separator) {
		return ""
	}
	return strings.TrimSpace(name)
}

func mediaKind(mimeType string) string {
	if strings.HasPrefix(strings.ToLower(strings.TrimSpace(mimeType)), "image/") {
		return "image"
	}
	return "file"
}

func copyFile(source, destination string) error {
	input, err := os.Open(source)
	if err != nil {
		return err
	}
	defer input.Close()

	output, err := os.OpenFile(destination, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}

	if _, err := io.Copy(output, input); err != nil {
		_ = output.Close()
		return err
	}
	return output.Close()
}
