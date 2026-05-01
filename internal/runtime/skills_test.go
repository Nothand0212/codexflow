package runtime

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDiscoverSkillsFromRootsSortsAndDeduplicates(t *testing.T) {
	root := t.TempDir()
	agentsRoot := filepath.Join(root, "agents")
	codexRoot := filepath.Join(root, "codex")

	writeTestSkill(t, filepath.Join(agentsRoot, "tdd", "SKILL.md"), "tdd", "Test-driven development")
	writeTestSkill(t, filepath.Join(agentsRoot, "brainstorming", "SKILL.md"), "brainstorming", "Creative planning")
	writeTestSkill(t, filepath.Join(codexRoot, "tdd", "SKILL.md"), "tdd", "Duplicate should not replace first")
	writeTestSkill(t, filepath.Join(codexRoot, "grill-with-docs", "SKILL.md"), "grill-with-docs", "Challenge plan with docs")

	skills := discoverSkillsFromRoots([]string{agentsRoot, codexRoot})

	if got, want := len(skills), 3; got != want {
		t.Fatalf("len(skills) = %d, want %d: %#v", got, want, skills)
	}
	assertSkill(t, skills[0], "brainstorming", "Creative planning")
	assertSkill(t, skills[1], "grill-with-docs", "Challenge plan with docs")
	assertSkill(t, skills[2], "tdd", "Test-driven development")
	if got, want := skills[2].InsertText, "$tdd "; got != want {
		t.Fatalf("InsertText = %q, want %q", got, want)
	}
}

func TestReadSkillFileFallsBackToDirectoryName(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "local-skill", "SKILL.md")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("# Local skill\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	skill, ok := readSkillFile(path, "")
	if !ok {
		t.Fatal("readSkillFile returned !ok")
	}
	if got, want := skill.Name, "local-skill"; got != want {
		t.Fatalf("Name = %q, want %q", got, want)
	}
}

func TestEnabledPluginSkillsUsePluginPrefix(t *testing.T) {
	home := t.TempDir()
	configPath := filepath.Join(home, ".codex", "config.toml")
	if err := os.MkdirAll(filepath.Dir(configPath), 0o755); err != nil {
		t.Fatal(err)
	}
	config := `
[plugins."codex@openai-codex"]
enabled = true

[plugins."disabled@openai-codex"]
enabled = false
`
	if err := os.WriteFile(configPath, []byte(config), 0o644); err != nil {
		t.Fatal(err)
	}

	localRoot := filepath.Join(home, ".codex", "skills")
	writeTestSkill(t, filepath.Join(localRoot, "skill-creator", "SKILL.md"), "skill-creator", "Local skill")
	writeTestSkill(
		t,
		filepath.Join(home, ".codex", "plugins", "cache", "openai-codex", "codex", "1.0.4", "skills", "codex-cli-runtime", "SKILL.md"),
		"codex-cli-runtime",
		"Runtime helper",
	)
	writeTestSkill(
		t,
		filepath.Join(home, ".codex", "plugins", "cache", "openai-codex", "disabled", "1.0.0", "skills", "disabled-skill", "SKILL.md"),
		"disabled-skill",
		"Should not appear",
	)

	skills := discoverSkillsFromScanRoots(defaultSkillScanRoots(home))

	names := make([]string, 0, len(skills))
	for _, skill := range skills {
		names = append(names, skill.Name)
	}
	assertContains(t, names, "codex:codex-cli-runtime")
	assertContains(t, names, "skill-creator")
	assertNotContains(t, names, "codex-cli-runtime")
	assertNotContains(t, names, "disabled:disabled-skill")
	assertNotContains(t, names, "disabled-skill")
}

func TestEnabledPluginSpecsParsesQuotedPluginSections(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "config.toml")
	content := `
[plugins."skill-creator@claude-plugins-official"]
enabled = true # enabled comment

[plugins."codex@openai-codex"]
enabled = false

[marketplaces.openai-codex]
enabled = true
`
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}

	specs := enabledPluginSpecs(path)

	if got, want := len(specs), 1; got != want {
		t.Fatalf("len(specs) = %d, want %d: %#v", got, want, specs)
	}
	if got, want := specs[0], "skill-creator@claude-plugins-official"; got != want {
		t.Fatalf("specs[0] = %q, want %q", got, want)
	}
}

func writeTestSkill(t *testing.T, path, name, description string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	content := "---\nname: " + name + "\ndescription: " + description + "\n---\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func assertSkill(t *testing.T, skill AgentSkill, name, description string) {
	t.Helper()
	if skill.Name != name {
		t.Fatalf("Name = %q, want %q", skill.Name, name)
	}
	if skill.Description != description {
		t.Fatalf("Description = %q, want %q", skill.Description, description)
	}
}

func assertContains(t *testing.T, values []string, want string) {
	t.Helper()
	for _, value := range values {
		if value == want {
			return
		}
	}
	t.Fatalf("%q not found in %#v", want, values)
}

func assertNotContains(t *testing.T, values []string, want string) {
	t.Helper()
	for _, value := range values {
		if value == want {
			t.Fatalf("%q unexpectedly found in %#v", want, values)
		}
	}
}
