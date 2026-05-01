package runtime

import (
	"reflect"
	"testing"
)

func TestCodexAutoApprovalResultPrefersSessionDecision(t *testing.T) {
	result, ok := codexAutoApprovalResult("item/commandExecution/requestApproval", map[string]any{
		"availableDecisions": []any{
			"accept",
			map[string]any{
				"acceptWithExecpolicyAmendment": map[string]any{
					"execpolicy_amendment": []any{"go", "test", "./..."},
				},
			},
			"acceptForSession",
			"cancel",
		},
	})
	if !ok {
		t.Fatalf("codexAutoApprovalResult() ok = false, want true")
	}

	payload, ok := result.(map[string]any)
	if !ok {
		t.Fatalf("result type = %T, want map[string]any", result)
	}
	if got := payload["decision"]; got != "acceptForSession" {
		t.Fatalf("decision = %#v, want acceptForSession", got)
	}
}

func TestCodexAutoApprovalResultUsesExecPolicyAmendment(t *testing.T) {
	amendment := map[string]any{
		"execpolicy_amendment": []any{"codex", "--help"},
	}
	result, ok := codexAutoApprovalResult("item/commandExecution/requestApproval", map[string]any{
		"availableDecisions": []any{
			"accept",
			map[string]any{"acceptWithExecpolicyAmendment": amendment},
			"cancel",
		},
	})
	if !ok {
		t.Fatalf("codexAutoApprovalResult() ok = false, want true")
	}

	payload := result.(map[string]any)
	decision, ok := payload["decision"].(map[string]any)
	if !ok {
		t.Fatalf("decision type = %T, want map[string]any", payload["decision"])
	}
	if got := decision["acceptWithExecpolicyAmendment"]; !reflect.DeepEqual(got, amendment) {
		t.Fatalf("acceptWithExecpolicyAmendment = %#v, want original amendment", got)
	}
}

func TestCodexAutoApprovalResultAcceptsPermissionsForSession(t *testing.T) {
	permissions := map[string]any{"network": []any{"api.openai.com"}}
	result, ok := codexAutoApprovalResult("item/permissions/requestApproval", map[string]any{
		"permissions": permissions,
	})
	if !ok {
		t.Fatalf("codexAutoApprovalResult() ok = false, want true")
	}

	payload := result.(map[string]any)
	if got := payload["permissions"]; !reflect.DeepEqual(got, permissions) {
		t.Fatalf("permissions = %#v, want original permissions", got)
	}
	if got := payload["scope"]; got != "session" {
		t.Fatalf("scope = %#v, want session", got)
	}
}

func TestCodexAutoApprovalResultIgnoresUserInput(t *testing.T) {
	if _, ok := codexAutoApprovalResult("item/tool/requestUserInput", map[string]any{}); ok {
		t.Fatalf("codexAutoApprovalResult() ok = true, want false")
	}
}
