package runtime

import (
	"os"
	"path/filepath"
	"slices"
	"strings"
)

type skillScanRoot struct {
	Path   string
	Prefix string
}

func (a *Agent) ListSkills() []AgentSkill {
	home, err := os.UserHomeDir()
	if err != nil || strings.TrimSpace(home) == "" {
		return []AgentSkill{}
	}
	return discoverSkillsFromScanRoots(defaultSkillScanRoots(home))
}

func defaultSkillScanRoots(home string) []skillScanRoot {
	roots := []skillScanRoot{
		{Path: filepath.Join(home, ".codex", "skills")},
		{Path: filepath.Join(home, ".agents", "skills")},
	}
	return append(roots, enabledPluginSkillRoots(home)...)
}

func discoverSkillsFromRoots(roots []string) []AgentSkill {
	scanRoots := make([]skillScanRoot, 0, len(roots))
	for _, root := range roots {
		scanRoots = append(scanRoots, skillScanRoot{Path: root})
	}
	return discoverSkillsFromScanRoots(scanRoots)
}

func discoverSkillsFromScanRoots(roots []skillScanRoot) []AgentSkill {
	byName := make(map[string]AgentSkill)
	for _, root := range roots {
		root.Path = strings.TrimSpace(root.Path)
		if root.Path == "" {
			continue
		}
		info, err := os.Stat(root.Path)
		if err != nil || !info.IsDir() {
			continue
		}
		_ = filepath.WalkDir(root.Path, func(path string, entry os.DirEntry, err error) error {
			if err != nil {
				return nil
			}
			if entry.IsDir() {
				return nil
			}
			if entry.Name() != "SKILL.md" {
				return nil
			}
			skill, ok := readSkillFile(path, root.Prefix)
			if !ok {
				return nil
			}
			key := strings.ToLower(skill.Name)
			if _, exists := byName[key]; !exists {
				byName[key] = skill
			}
			return nil
		})
	}

	skills := make([]AgentSkill, 0, len(byName))
	for _, skill := range byName {
		skills = append(skills, skill)
	}
	slices.SortFunc(skills, func(left, right AgentSkill) int {
		leftName := strings.ToLower(left.Name)
		rightName := strings.ToLower(right.Name)
		if leftName == rightName {
			return strings.Compare(left.Name, right.Name)
		}
		return strings.Compare(leftName, rightName)
	})
	return skills
}

func readSkillFile(path, prefix string) (AgentSkill, bool) {
	content, err := os.ReadFile(path)
	if err != nil {
		return AgentSkill{}, false
	}

	name, description := parseSkillFrontmatter(string(content))
	name = strings.TrimSpace(name)
	if name == "" {
		name = strings.TrimSpace(filepath.Base(filepath.Dir(path)))
	}
	if name == "" {
		return AgentSkill{}, false
	}
	if prefix != "" && !strings.Contains(name, ":") {
		name = strings.TrimSuffix(prefix, ":") + ":" + name
	}

	return AgentSkill{
		Name:        name,
		Description: strings.TrimSpace(description),
		InsertText:  "$" + name + " ",
	}, true
}

func parseSkillFrontmatter(content string) (string, string) {
	content = strings.ReplaceAll(content, "\r\n", "\n")
	if !strings.HasPrefix(content, "---\n") {
		return "", ""
	}
	rest := strings.TrimPrefix(content, "---\n")
	end := strings.Index(rest, "\n---")
	if end < 0 {
		return "", ""
	}

	var name string
	var description string
	for _, line := range strings.Split(rest[:end], "\n") {
		key, value, ok := strings.Cut(line, ":")
		if !ok {
			continue
		}
		value = trimYAMLScalar(value)
		switch strings.TrimSpace(key) {
		case "name":
			name = value
		case "description":
			description = value
		}
	}
	return name, description
}

func trimYAMLScalar(value string) string {
	value = strings.TrimSpace(value)
	if len(value) >= 2 {
		first := value[0]
		last := value[len(value)-1]
		if (first == '\'' && last == '\'') || (first == '"' && last == '"') {
			return strings.TrimSpace(value[1 : len(value)-1])
		}
	}
	return value
}

func enabledPluginSkillRoots(home string) []skillScanRoot {
	specs := enabledPluginSpecs(filepath.Join(home, ".codex", "config.toml"))
	if len(specs) == 0 {
		return []skillScanRoot{}
	}

	cacheRoot := filepath.Join(home, ".codex", "plugins", "cache")
	roots := make([]skillScanRoot, 0, len(specs))
	for _, spec := range specs {
		plugin, marketplace, ok := strings.Cut(spec, "@")
		if !ok || plugin == "" || marketplace == "" {
			continue
		}
		base := filepath.Join(cacheRoot, marketplace, plugin)
		prefix := plugin + ":"
		roots = appendPluginSkillRoot(roots, filepath.Join(base, "skills"), prefix)

		entries, err := os.ReadDir(base)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if !entry.IsDir() {
				continue
			}
			roots = appendPluginSkillRoot(
				roots,
				filepath.Join(base, entry.Name(), "skills"),
				prefix,
			)
		}
	}
	return roots
}

func appendPluginSkillRoot(roots []skillScanRoot, path, prefix string) []skillScanRoot {
	info, err := os.Stat(path)
	if err != nil || !info.IsDir() {
		return roots
	}
	return append(roots, skillScanRoot{Path: path, Prefix: prefix})
}

func enabledPluginSpecs(configPath string) []string {
	content, err := os.ReadFile(configPath)
	if err != nil {
		return []string{}
	}

	enabled := make(map[string]bool)
	current := ""
	currentEnabled := false
	flush := func() {
		if current != "" && currentEnabled {
			enabled[current] = true
		}
	}

	for _, rawLine := range strings.Split(string(content), "\n") {
		line := strings.TrimSpace(stripTOMLComment(rawLine))
		if line == "" {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			flush()
			current = parsePluginSection(line)
			currentEnabled = false
			continue
		}
		if current == "" {
			continue
		}
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			continue
		}
		if strings.TrimSpace(key) == "enabled" &&
			strings.EqualFold(strings.TrimSpace(value), "true") {
			currentEnabled = true
		}
	}
	flush()

	specs := make([]string, 0, len(enabled))
	for spec := range enabled {
		specs = append(specs, spec)
	}
	slices.Sort(specs)
	return specs
}

func parsePluginSection(line string) string {
	section := strings.TrimSuffix(strings.TrimPrefix(line, "["), "]")
	if !strings.HasPrefix(section, "plugins.") {
		return ""
	}
	spec := strings.TrimSpace(strings.TrimPrefix(section, "plugins."))
	spec = strings.Trim(spec, `"`)
	if !strings.Contains(spec, "@") {
		return ""
	}
	return spec
}

func stripTOMLComment(line string) string {
	inSingle := false
	inDouble := false
	for index, char := range line {
		switch char {
		case '\'':
			if !inDouble {
				inSingle = !inSingle
			}
		case '"':
			if !inSingle {
				inDouble = !inDouble
			}
		case '#':
			if !inSingle && !inDouble {
				return line[:index]
			}
		}
	}
	return line
}
