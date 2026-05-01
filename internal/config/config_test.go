package config

import "testing"

func TestLoadCodexAutoApprove(t *testing.T) {
	t.Setenv("CODEXFLOW_CODEX_AUTO_APPROVE", "true")

	cfg := Load()
	if !cfg.CodexAutoApprove {
		t.Fatalf("CodexAutoApprove = false, want true")
	}
}

func TestLoadCodexAutoApproveInvalidFallsBack(t *testing.T) {
	t.Setenv("CODEXFLOW_CODEX_AUTO_APPROVE", "definitely")

	cfg := Load()
	if cfg.CodexAutoApprove {
		t.Fatalf("CodexAutoApprove = true, want fallback false")
	}
}
