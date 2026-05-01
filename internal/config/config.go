package config

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Config struct {
	ListenAddr       string
	CodexPath        string
	ClaudePath       string
	CodexAutoApprove bool
	RefreshInterval  time.Duration
	StateDBPath      string
	MediaDir         string
}

func Load() Config {
	return Config{
		ListenAddr:       getenv("CODEXFLOW_LISTEN_ADDR", "127.0.0.1:4318"),
		CodexPath:        getenv("CODEXFLOW_CODEX_PATH", "codex"),
		ClaudePath:       getenv("CODEXFLOW_CLAUDE_PATH", "claude"),
		CodexAutoApprove: getBoolEnv("CODEXFLOW_CODEX_AUTO_APPROVE", false),
		RefreshInterval:  getDurationEnv("CODEXFLOW_REFRESH_INTERVAL", 12*time.Second),
		StateDBPath:      getenv("CODEXFLOW_STATE_DB_PATH", defaultStateDBPath()),
		MediaDir:         getenv("CODEXFLOW_MEDIA_DIR", defaultMediaDir()),
	}
}

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func getDurationEnv(key string, fallback time.Duration) time.Duration {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}

	parsed, err := time.ParseDuration(value)
	if err != nil || parsed <= 0 {
		return fallback
	}
	return parsed
}

func getBoolEnv(key string, fallback bool) bool {
	value := strings.ToLower(strings.TrimSpace(os.Getenv(key)))
	if value == "" {
		return fallback
	}
	switch value {
	case "1", "true", "t", "yes", "y", "on":
		return true
	case "0", "false", "f", "no", "n", "off":
		return false
	default:
		return fallback
	}
}

func defaultStateDBPath() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "./codexflow-state.db"
	}
	return filepath.Join(home, ".codexflow", "state.db")
}

func defaultMediaDir() string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return "./codexflow-media"
	}
	return filepath.Join(home, ".codexflow", "media")
}
