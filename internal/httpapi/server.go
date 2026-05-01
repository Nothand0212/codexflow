package httpapi

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"codexflow/internal/config"
	"codexflow/internal/runtime"
)

type Server struct {
	agent   *runtime.Agent
	logger  *slog.Logger
	mux     *http.ServeMux
	uploads *imageUploadStore
	media   *sessionMediaStore
}

func NewServer(agent *runtime.Agent, logger *slog.Logger, cfg config.Config) *Server {
	server := &Server{
		agent:   agent,
		logger:  logger,
		mux:     http.NewServeMux(),
		uploads: newImageUploadStore(),
		media:   initializeSessionMediaStore(logger, cfg.MediaDir),
	}
	server.routes()
	return server
}

func initializeSessionMediaStore(logger *slog.Logger, mediaDir string) *sessionMediaStore {
	store, err := newSessionMediaStore(mediaDir)
	if err == nil {
		return store
	}
	if logger != nil {
		logger.Warn("failed to initialize media store", "dir", mediaDir, "error", err)
	}

	fallback := filepath.Join(os.TempDir(), "codexflow", "media")
	store, err = newSessionMediaStore(fallback)
	if err == nil {
		return store
	}
	if logger != nil {
		logger.Warn("failed to initialize fallback media store", "dir", fallback, "error", err)
	}
	return nil
}

func (s *Server) Handler() http.Handler {
	return s.withLogging(s.withCORS(s.mux))
}

func (s *Server) routes() {
	s.mux.HandleFunc("/healthz", s.handleHealth)
	s.mux.HandleFunc("/api/v1/dashboard", s.handleDashboard)
	s.mux.HandleFunc("/api/v1/events", s.handleEvents)
	s.mux.HandleFunc("/api/v1/skills", s.handleSkills)
	s.mux.HandleFunc("/api/v1/sessions", s.handleSessions)
	s.mux.HandleFunc("/api/v1/sessions/", s.handleSessionByID)
	s.mux.HandleFunc("/api/v1/approvals", s.handleApprovals)
	s.mux.HandleFunc("/api/v1/approvals/", s.handleApprovalByID)
	s.mux.HandleFunc("/api/v1/uploads/image", s.handleImageUpload)
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":        true,
		"timestamp": time.Now(),
	})
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, s.agent.Dashboard())
}

func (s *Server) handleSkills(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"data": s.agent.ListSkills(),
	})
}

func (s *Server) handleSessions(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		writeJSON(w, http.StatusOK, map[string]any{
			"data": s.agent.ListSessions(),
		})
	case http.MethodPost:
		var request struct {
			Action string `json:"action"`
			CWD    string `json:"cwd"`
			Prompt string `json:"prompt"`
			Agent  string `json:"agent"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()

		switch request.Action {
		case "refresh":
			if err := s.agent.Refresh(ctx); err != nil {
				writeError(w, http.StatusBadGateway, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]any{"ok": true})
		case "start":
			cwd := normalizeCWD(request.CWD)
			prompt := strings.TrimSpace(request.Prompt)

			if cwd == "" {
				writeErrorMessage(w, http.StatusBadRequest, "working directory is required")
				return
			}
			if !filepath.IsAbs(cwd) {
				writeErrorMessage(w, http.StatusBadRequest, "working directory must be an absolute path")
				return
			}
			if prompt == "" {
				writeErrorMessage(w, http.StatusBadRequest, "first prompt is required to materialize a managed session")
				return
			}
			session, err := s.agent.StartSession(ctx, cwd, prompt, request.Agent)
			if err != nil {
				writeError(w, http.StatusBadGateway, err)
				return
			}
			writeJSON(w, http.StatusCreated, session)
		default:
			writeErrorMessage(w, http.StatusBadRequest, "unsupported sessions action")
		}
	default:
		methodNotAllowed(w)
	}
}

func (s *Server) handleSessionByID(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/api/v1/sessions/")
	if path == "" {
		writeErrorMessage(w, http.StatusNotFound, "session not found")
		return
	}

	parts := strings.Split(strings.Trim(path, "/"), "/")
	sessionID := parts[0]

	if len(parts) == 3 && parts[1] == "media" {
		if r.Method != http.MethodGet {
			methodNotAllowed(w)
			return
		}
		s.handleSessionMedia(w, r, sessionID, parts[2])
		return
	}

	if len(parts) == 1 {
		if r.Method != http.MethodGet {
			methodNotAllowed(w)
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()

		detail, err := s.agent.SessionDetailPage(ctx, sessionID, parseSessionDetailPageRequest(r))
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		s.overlaySessionMedia(&detail)
		writeJSON(w, http.StatusOK, detail)
		return
	}

	action := strings.Join(parts[1:], "/")
	switch action {
	case "resume":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		session, err := s.agent.ResumeSession(ctx, sessionID)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, session)
	case "end":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		if err := s.agent.EndSession(ctx, sessionID); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case "archive":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
		defer cancel()
		if err := s.agent.ArchiveSession(ctx, sessionID); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case "turns/start":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var request struct {
			Prompt string `json:"prompt"`
			Inputs []struct {
				Type     string `json:"type"`
				Text     string `json:"text"`
				UploadID string `json:"uploadId"`
			} `json:"inputs"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		buildResult, err := s.buildTurnInput(request.Prompt, request.Inputs)
		if err != nil {
			writeErrorMessage(w, http.StatusBadRequest, err.Error())
			return
		}
		turn, err := s.agent.StartTurn(ctx, sessionID, buildResult.Inputs)
		if err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		if err := s.attachUploadsToFirstUserMessage(sessionID, &turn, buildResult.Uploads); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusCreated, turn)
	case "turns/steer":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var request struct {
			TurnID string `json:"turnId"`
			Prompt string `json:"prompt"`
			Inputs []struct {
				Type     string `json:"type"`
				Text     string `json:"text"`
				UploadID string `json:"uploadId"`
			} `json:"inputs"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
		defer cancel()
		buildResult, err := s.buildTurnInput(request.Prompt, request.Inputs)
		if err != nil {
			writeErrorMessage(w, http.StatusBadRequest, err.Error())
			return
		}
		if err := s.agent.SteerTurn(ctx, sessionID, request.TurnID, buildResult.Inputs); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		if err := s.attachSteerUploads(ctx, sessionID, request.TurnID, buildResult.Uploads); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	case "turns/interrupt":
		if r.Method != http.MethodPost {
			methodNotAllowed(w)
			return
		}
		var request struct {
			TurnID string `json:"turnId"`
		}
		if !decodeJSON(w, r, &request) {
			return
		}

		ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
		defer cancel()
		if err := s.agent.InterruptTurn(ctx, sessionID, request.TurnID); err != nil {
			writeError(w, http.StatusBadGateway, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true})
	default:
		writeErrorMessage(w, http.StatusNotFound, fmt.Sprintf("unsupported session action %q", action))
	}
}

func parseSessionDetailPageRequest(r *http.Request) runtime.SessionDetailPageRequest {
	query := r.URL.Query()
	return runtime.SessionDetailPageRequest{
		TurnOffset: parseNonNegativeInt(query.Get("turnOffset")),
		TurnLimit:  parseNonNegativeInt(query.Get("turnLimit")),
	}
}

func parseNonNegativeInt(value string) int {
	if strings.TrimSpace(value) == "" {
		return 0
	}
	parsed, err := strconv.Atoi(value)
	if err != nil || parsed < 0 {
		return 0
	}
	return parsed
}

func (s *Server) handleSessionMedia(w http.ResponseWriter, r *http.Request, sessionID, mediaID string) {
	if s.media == nil {
		writeErrorMessage(w, http.StatusNotFound, "media not found")
		return
	}

	mediaFile, err := s.media.OpenMedia(sessionID, mediaID)
	if err != nil {
		writeErrorMessage(w, http.StatusNotFound, "media not found")
		return
	}
	defer mediaFile.File.Close()

	stat, err := mediaFile.File.Stat()
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}

	contentType := strings.TrimSpace(mediaFile.Media.MIMEType)
	if contentType == "" {
		contentType = detectMediaContentType(mediaFile.File, mediaFile.Media.Name)
	}
	if contentType != "" {
		w.Header().Set("Content-Type", contentType)
	}

	http.ServeContent(w, r, mediaFile.Media.Name, stat.ModTime(), mediaFile.File)
}

func detectMediaContentType(file *os.File, name string) string {
	if contentType := mime.TypeByExtension(filepath.Ext(strings.TrimSpace(name))); contentType != "" {
		return contentType
	}

	buffer := make([]byte, 512)
	n, err := file.Read(buffer)
	_, _ = file.Seek(0, io.SeekStart)
	if err != nil && err != io.EOF {
		return ""
	}
	if n == 0 {
		return ""
	}
	return http.DetectContentType(buffer[:n])
}

func (s *Server) overlaySessionMedia(detail *runtime.SessionDetail) {
	if s.media == nil || detail == nil {
		return
	}
	sessionID := detail.Summary.ID
	for turnIndex := range detail.Turns {
		turn := &detail.Turns[turnIndex]
		for itemIndex := range turn.Items {
			item := &turn.Items[itemIndex]
			for _, media := range s.media.MediaForItem(sessionID, turn.ID, item.ID) {
				if hasMediaAttachment(item.Media, media) {
					continue
				}
				item.Media = append(item.Media, media)
			}
		}
	}
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

func (s *Server) handleApprovals(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"data": s.agent.PendingRequests(),
	})
}

func (s *Server) handleApprovalByID(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}

	path := strings.TrimPrefix(r.URL.Path, "/api/v1/approvals/")
	parts := strings.Split(strings.Trim(path, "/"), "/")
	if len(parts) != 2 || parts[1] != "resolve" {
		writeErrorMessage(w, http.StatusNotFound, "approval endpoint not found")
		return
	}

	var request struct {
		Result json.RawMessage `json:"result"`
	}
	if !decodeJSON(w, r, &request) {
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()

	if err := s.agent.ResolveRequest(ctx, parts[0], request.Result); err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *Server) handleEvents(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		methodNotAllowed(w)
		return
	}

	flusher, ok := w.(http.Flusher)
	if !ok {
		writeErrorMessage(w, http.StatusInternalServerError, "streaming is not supported")
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")

	subscription := s.agent.Subscribe()
	defer s.agent.Unsubscribe(subscription)

	ticker := time.NewTicker(20 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-r.Context().Done():
			return
		case event := <-subscription:
			data, _ := json.Marshal(event)
			_, _ = fmt.Fprintf(w, "event: %s\n", event.Type)
			_, _ = fmt.Fprintf(w, "data: %s\n\n", data)
			flusher.Flush()
		case <-ticker.C:
			_, _ = fmt.Fprint(w, ": ping\n\n")
			flusher.Flush()
		}
	}
}

func (s *Server) handleImageUpload(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		methodNotAllowed(w)
		return
	}
	if err := r.ParseMultipartForm(maxUploadImageBytes + (1 * 1024 * 1024)); err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "invalid multipart form payload")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "missing image file in multipart field 'file'")
		return
	}
	defer file.Close()

	payload, err := io.ReadAll(io.LimitReader(file, maxUploadImageBytes+1))
	if err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "failed to read uploaded image")
		return
	}
	if len(payload) == 0 {
		writeErrorMessage(w, http.StatusBadRequest, "uploaded image is empty")
		return
	}
	if len(payload) > maxUploadImageBytes {
		writeErrorMessage(w, http.StatusBadRequest, "image exceeds 15MB size limit")
		return
	}
	if !strings.HasPrefix(http.DetectContentType(payload), "image/") {
		writeErrorMessage(w, http.StatusBadRequest, "uploaded file must be an image")
		return
	}

	name := strings.TrimSpace(header.Filename)
	if name == "" {
		name = "upload-image"
	}
	item, err := s.uploads.Save(name, payload)
	if err != nil {
		writeError(w, http.StatusBadGateway, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]any{
		"id":   item.ID,
		"name": item.Name,
		"size": item.Size,
	})
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

func (s *Server) buildTurnInput(
	legacyPrompt string,
	inputs []struct {
		Type     string `json:"type"`
		Text     string `json:"text"`
		UploadID string `json:"uploadId"`
	},
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
			upload, err := s.uploads.Resolve(input.UploadID)
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

func (s *Server) attachUploadsToFirstUserMessage(sessionID string, turn *runtime.TurnDetail, uploads []resolvedImageUpload) error {
	if s.media == nil || turn == nil || len(uploads) == 0 {
		return nil
	}
	for index := range turn.Items {
		if turn.Items[index].Type != "userMessage" {
			continue
		}
		if err := s.attachUploadsToItem(sessionID, turn.ID, turn.Items[index].ID, uploads); err != nil {
			return err
		}
		turn.Items[index].Media = s.media.MediaForItem(sessionID, turn.ID, turn.Items[index].ID)
		return nil
	}
	return nil
}

func (s *Server) attachSteerUploads(ctx context.Context, sessionID, turnID string, uploads []resolvedImageUpload) error {
	if s.media == nil || len(uploads) == 0 {
		return nil
	}
	detail, err := s.agent.SessionDetailPage(ctx, sessionID, runtime.SessionDetailPageRequest{TurnLimit: runtime.MaxSessionDetailTurnLimit})
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
			return s.attachUploadsToItem(sessionID, turn.ID, itemID, uploads)
		}
		return fmt.Errorf("turn %q has no user message for image attachment", turn.ID)
	}
	if targetTurnID != "" {
		return fmt.Errorf("turn %q could not be found for image attachment", targetTurnID)
	}
	return nil
}

func latestUserMessageItemID(turn runtime.TurnDetail) (string, bool) {
	for index := len(turn.Items) - 1; index >= 0; index-- {
		if turn.Items[index].Type == "userMessage" {
			return turn.Items[index].ID, true
		}
	}
	return "", false
}

func (s *Server) attachUploadsToItem(sessionID, turnID, itemID string, uploads []resolvedImageUpload) error {
	for _, upload := range uploads {
		if _, err := s.media.AttachUpload(sessionMediaUpload{
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

func composeTextInput(prompt string) map[string]any {
	return map[string]any{
		"type":          "text",
		"text":          prompt,
		"text_elements": []any{},
	}
}

func (s *Server) withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		s.logger.Info("http request", "method", r.Method, "path", r.URL.Path, "duration", time.Since(start))
	})
}

func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := strings.TrimSpace(r.Header.Get("Origin"))
		if origin != "" && isAllowedOrigin(origin) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization, Accept, Cache-Control")
			w.Header().Set("Access-Control-Expose-Headers", "Content-Type")
		}

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

func methodNotAllowed(w http.ResponseWriter) {
	writeErrorMessage(w, http.StatusMethodNotAllowed, "method not allowed")
}

func decodeJSON(w http.ResponseWriter, r *http.Request, target interface{}) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(target); err != nil {
		writeErrorMessage(w, http.StatusBadRequest, "invalid json body")
		return false
	}
	return true
}

func writeJSON(w http.ResponseWriter, status int, payload interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}

func writeError(w http.ResponseWriter, status int, err error) {
	writeErrorMessage(w, status, err.Error())
}

func writeErrorMessage(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, map[string]any{
		"error": message,
	})
}

func normalizeCWD(value string) string {
	trimmed := strings.TrimSpace(value)
	if trimmed == "" {
		return ""
	}

	if trimmed == "~" {
		if home, err := os.UserHomeDir(); err == nil {
			return home
		}
		return trimmed
	}

	if strings.HasPrefix(trimmed, "~/") {
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, strings.TrimPrefix(trimmed, "~/"))
		}
	}

	return trimmed
}

func isAllowedOrigin(origin string) bool {
	override := strings.TrimSpace(os.Getenv("CODEXFLOW_ALLOWED_ORIGINS"))
	if override != "" {
		return matchesAllowedOrigins(origin, override)
	}

	return strings.HasPrefix(origin, "http://localhost:") ||
		strings.HasPrefix(origin, "http://127.0.0.1:") ||
		strings.HasPrefix(origin, "http://[::1]:") ||
		strings.HasPrefix(origin, "https://localhost:") ||
		strings.HasPrefix(origin, "https://127.0.0.1:") ||
		strings.HasPrefix(origin, "https://[::1]:") ||
		strings.HasPrefix(origin, "chrome-extension://")
}

func matchesAllowedOrigins(origin, raw string) bool {
	for _, entry := range strings.Split(raw, ",") {
		pattern := strings.TrimSpace(entry)
		if pattern == "" {
			continue
		}
		if pattern == "*" || pattern == origin {
			return true
		}
		if strings.HasSuffix(pattern, "*") {
			prefix := strings.TrimSuffix(pattern, "*")
			if strings.HasPrefix(origin, prefix) {
				return true
			}
		}
	}
	return false
}
