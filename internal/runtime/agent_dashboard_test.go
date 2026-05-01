package runtime

import (
	"encoding/json"
	"testing"

	"codexflow/internal/codex"
	"codexflow/internal/store"
)

func TestDashboardLoadedSessionsExcludeEndedSessions(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("create session store: %v", err)
	}

	sessionStore.ReplaceSessions([]codex.Thread{
		{
			ID:            "ended-thread",
			ModelProvider: "OpenAI",
			CreatedAt:     100,
			UpdatedAt:     200,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/ended",
		},
		{
			ID:            "active-thread",
			ModelProvider: "OpenAI",
			CreatedAt:     101,
			UpdatedAt:     201,
			Status:        codex.ThreadStatus{Type: "active"},
			CWD:           "/tmp/active",
		},
	}, map[string]bool{
		"ended-thread":  true,
		"active-thread": true,
	})

	sessionStore.SetSessionManaged("ended-thread", true)
	sessionStore.SetSessionManaged("active-thread", true)
	sessionStore.SetSessionEnded("ended-thread", true)

	agent := &Agent{store: sessionStore}
	dashboard := agent.Dashboard()

	if got, want := dashboard.Stats.LoadedSessions, 1; got != want {
		t.Fatalf("loaded sessions = %d, want %d", got, want)
	}

	if got, want := dashboard.Stats.ActiveSessions, 1; got != want {
		t.Fatalf("active sessions = %d, want %d", got, want)
	}

	summaries := dashboard.Sessions
	if len(summaries) != 2 {
		t.Fatalf("sessions count = %d, want 2", len(summaries))
	}

	for _, session := range summaries {
		if session.ID == "ended-thread" && session.Loaded {
			t.Fatalf("ended session should not be marked loaded in API summary")
		}
	}
}

func TestDashboardLoadedSessionsCountOnlyManagedSessions(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("create session store: %v", err)
	}

	sessionStore.ReplaceSessions([]codex.Thread{
		{
			ID:            "runtime-loaded-only",
			ModelProvider: "OpenAI",
			CreatedAt:     100,
			UpdatedAt:     200,
			Status:        codex.ThreadStatus{Type: "notLoaded"},
			CWD:           "/tmp/runtime",
		},
		{
			ID:            "codexflow-managed",
			ModelProvider: "OpenAI",
			CreatedAt:     101,
			UpdatedAt:     201,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/managed",
		},
	}, map[string]bool{
		"runtime-loaded-only": true,
		"codexflow-managed":   true,
	})
	sessionStore.SetSessionManaged("codexflow-managed", true)

	agent := &Agent{store: sessionStore}
	dashboard := agent.Dashboard()

	if got, want := dashboard.Stats.LoadedSessions, 1; got != want {
		t.Fatalf("loaded sessions = %d, want %d", got, want)
	}

	byID := make(map[string]SessionSummary)
	for _, summary := range dashboard.Sessions {
		byID[summary.ID] = summary
	}
	if byID["runtime-loaded-only"].Loaded {
		t.Fatalf("runtime-loaded-only should not be user-visible loaded")
	}
	if got := byID["runtime-loaded-only"].LifecycleStage; got == "managed" {
		t.Fatalf("runtime-loaded-only lifecycle = %q, want non-managed", got)
	}
	if !byID["codexflow-managed"].Loaded {
		t.Fatalf("codexflow-managed should be user-visible loaded")
	}
}

func TestDashboardTotalSessionsCountOnlyUserInitiatedSessions(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("create session store: %v", err)
	}

	sessionStore.ReplaceSessions([]codex.Thread{
		{
			ID:            "cli-root",
			ModelProvider: "OpenAI",
			CreatedAt:     100,
			UpdatedAt:     200,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/cli",
			Source:        json.RawMessage(`"cli"`),
		},
		{
			ID:            "managed-codexflow",
			ModelProvider: "OpenAI",
			CreatedAt:     101,
			UpdatedAt:     201,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/managed",
			Source:        json.RawMessage(`"vscode"`),
		},
		{
			ID:            "external-import",
			ModelProvider: "OpenAI",
			CreatedAt:     102,
			UpdatedAt:     202,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/external",
			Source:        json.RawMessage(`"vscode"`),
		},
		{
			ID:            "agent-spawned",
			ModelProvider: "OpenAI",
			CreatedAt:     103,
			UpdatedAt:     203,
			Status:        codex.ThreadStatus{Type: "idle"},
			CWD:           "/tmp/subagent",
			Source:        json.RawMessage(`{"subagent":{"thread_spawn":{"parent_thread_id":"cli-root","depth":1}}}`),
		},
	}, map[string]bool{
		"managed-codexflow": true,
	})
	sessionStore.SetSessionManaged("managed-codexflow", true)

	agent := &Agent{store: sessionStore}
	dashboard := agent.Dashboard()

	if got, want := dashboard.Stats.TotalSessions, 2; got != want {
		t.Fatalf("total sessions = %d, want %d", got, want)
	}

	byID := make(map[string]SessionSummary)
	for _, summary := range dashboard.Sessions {
		byID[summary.ID] = summary
	}
	if !byID["cli-root"].UserInitiated {
		t.Fatalf("cli-root should be user initiated")
	}
	if !byID["managed-codexflow"].UserInitiated {
		t.Fatalf("managed-codexflow should be user initiated")
	}
	if byID["external-import"].UserInitiated {
		t.Fatalf("external-import should not be user initiated")
	}
	if byID["agent-spawned"].UserInitiated {
		t.Fatalf("agent-spawned should not be user initiated")
	}
}

func TestEndedSessionSummaryForcesIdleStatus(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("create session store: %v", err)
	}

	sessionStore.ReplaceSessions([]codex.Thread{
		{
			ID:            "ended-thread",
			ModelProvider: "OpenAI",
			CreatedAt:     100,
			UpdatedAt:     200,
			Status:        codex.ThreadStatus{Type: "active"},
			CWD:           "/tmp/ended",
		},
	}, map[string]bool{
		"ended-thread": true,
	})
	sessionStore.SetSessionEnded("ended-thread", true)

	record, ok := sessionStore.SnapshotSession("ended-thread")
	if !ok {
		t.Fatalf("SnapshotSession() missing record")
	}

	summary := toSessionSummary(record, 0)
	if got := summary.Status; got != "idle" {
		t.Fatalf("summary.Status = %q, want %q", got, "idle")
	}
}

func TestSessionSummaryIncludesRuntimeAttachMode(t *testing.T) {
	sessionStore, err := store.New(nil)
	if err != nil {
		t.Fatalf("create session store: %v", err)
	}

	sessionStore.UpsertThread(codex.Thread{
		ID:            "claude:thread-1",
		ModelProvider: "Anthropic",
		CreatedAt:     100,
		UpdatedAt:     200,
		Status:        codex.ThreadStatus{Type: "idle", ActiveFlags: []string{"claudeRuntimeAvailable"}},
		CWD:           "/tmp/claude",
	})
	sessionStore.SetRuntimeAttachMode("claude:thread-1", "resumed_existing")

	record, ok := sessionStore.SnapshotSession("claude:thread-1")
	if !ok {
		t.Fatalf("SnapshotSession() missing record")
	}
	summary := toSessionSummary(record, 0)
	if got := summary.RuntimeAttachMode; got != "resumed_existing" {
		t.Fatalf("summary.RuntimeAttachMode = %q, want %q", got, "resumed_existing")
	}
}
