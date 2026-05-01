package runtime

import (
	"fmt"
	"testing"

	"codexflow/internal/codex"
	"codexflow/internal/store"
)

func TestSessionDetailPageReturnsNewestTurnWindow(t *testing.T) {
	record := store.SessionRecord{
		Thread: codex.Thread{
			ID:            "thread-paged",
			ModelProvider: "OpenAI",
			CWD:           "/tmp/paged",
			Status:        codex.ThreadStatus{Type: "idle"},
			Turns:         testTurns(12),
		},
	}

	detail := toSessionDetailPage(record, 0, SessionDetailPageRequest{
		TurnOffset: 0,
		TurnLimit:  5,
	})

	if got, want := turnIDs(detail.Turns), []string{"turn-07", "turn-08", "turn-09", "turn-10", "turn-11"}; fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("turn IDs = %v, want %v", got, want)
	}
	if got, want := detail.Page.TotalTurns, 12; got != want {
		t.Fatalf("total turns = %d, want %d", got, want)
	}
	if got, want := detail.Page.TurnOffset, 0; got != want {
		t.Fatalf("turn offset = %d, want %d", got, want)
	}
	if got, want := detail.Page.TurnLimit, 5; got != want {
		t.Fatalf("turn limit = %d, want %d", got, want)
	}
	if !detail.Page.HasMoreBefore {
		t.Fatalf("has more before = false, want true")
	}
}

func TestSessionDetailPageUsesOffsetFromNewestTurn(t *testing.T) {
	record := store.SessionRecord{
		Thread: codex.Thread{
			ID:            "thread-paged",
			ModelProvider: "OpenAI",
			CWD:           "/tmp/paged",
			Status:        codex.ThreadStatus{Type: "idle"},
			Turns:         testTurns(12),
		},
	}

	detail := toSessionDetailPage(record, 0, SessionDetailPageRequest{
		TurnOffset: 5,
		TurnLimit:  5,
	})

	if got, want := turnIDs(detail.Turns), []string{"turn-02", "turn-03", "turn-04", "turn-05", "turn-06"}; fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("turn IDs = %v, want %v", got, want)
	}
	if !detail.Page.HasMoreBefore {
		t.Fatalf("has more before = false, want true")
	}
}

func testTurns(count int) []codex.Turn {
	turns := make([]codex.Turn, 0, count)
	for index := 0; index < count; index++ {
		turns = append(turns, codex.Turn{
			ID:     fmt.Sprintf("turn-%02d", index),
			Status: "completed",
			Items: []map[string]any{
				{"id": fmt.Sprintf("user-%02d", index), "type": "userMessage", "text": fmt.Sprintf("user %02d", index)},
				{"id": fmt.Sprintf("agent-%02d", index), "type": "agentMessage", "text": fmt.Sprintf("agent %02d", index)},
			},
		})
	}
	return turns
}

func turnIDs(turns []TurnDetail) []string {
	ids := make([]string, 0, len(turns))
	for _, turn := range turns {
		ids = append(ids, turn.ID)
	}
	return ids
}
