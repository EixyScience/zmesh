package scalefsconf

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/ini.v1"
)

type Paths struct {
	Main         string // e.g. ./main
	StateDir     string // e.g. ./scalefs.runtime.d/scalefs.state
	WatchRoot    string // e.g. ./main
	WatchExclude []string
}

// LoadPaths loads scalefs.ini and include dirs.
// Merge order: scalefs.ini -> global.d/*.ini -> local.d/*.ini  (last wins)
func LoadPaths(scalefsRoot string) (Paths, error) {
	if scalefsRoot == "" {
		return Paths{}, fmt.Errorf("scalefsconf: scalefsRoot empty")
	}

	root := filepath.Clean(scalefsRoot)
	iniPath := filepath.Join(root, "scalefs.ini")
	if _, err := os.Stat(iniPath); err != nil {
		return Paths{}, fmt.Errorf("scalefsconf: scalefs.ini not found: %w", err)
	}

	// Disable "shadowing" with env expansion; keep plain INI.
	loadOpt := ini.LoadOptions{
		IgnoreInlineComment: true,
	}

	base, err := ini.LoadSources(loadOpt, iniPath)
	if err != nil {
		return Paths{}, fmt.Errorf("scalefsconf: load scalefs.ini: %w", err)
	}

	// Merge include dirs
	for _, p := range globSorted(filepath.Join(root, "scalefs.global.d", "*.ini")) {
		_ = base.Append(p)
	}
	for _, p := range globSorted(filepath.Join(root, "scalefs.local.d", "*.ini")) {
		_ = base.Append(p)
	}

	sec := base.Section("paths")

	main := strings.TrimSpace(sec.Key("main").String())
	if main == "" {
		main = "./main"
	}

	stateDir := strings.TrimSpace(sec.Key("state_dir").String())
	if stateDir == "" {
		// NEW DEFAULT NAME
		stateDir = "./scalefs.runtime.d/scalefs.state"
	}

	watchRoot := strings.TrimSpace(sec.Key("watch_root").String())
	if watchRoot == "" {
		watchRoot = "./main"
	}

	ex := strings.TrimSpace(sec.Key("watch_exclude").String())
	var excludes []string
	if ex != "" {
		for _, s := range strings.Split(ex, ",") {
			s = strings.TrimSpace(s)
			if s != "" {
				excludes = append(excludes, s)
			}
		}
	}

	// Always exclude internal dirs by default (safe defaults)
	excludes = append(excludes,
		"./scalefs.runtime.d/**",
		"./scalefs.local.d/**",
		".shadow/**", ".latest/**", ".tmp/**", ".snapshot/**",
		".git/**",
	)

	return Paths{
		Main:         main,
		StateDir:     stateDir,
		WatchRoot:    watchRoot,
		WatchExclude: excludes,
	}, nil
}

func globSorted(pattern string) []string {
	m, _ := filepath.Glob(pattern)
	// filepath.Glob returns sorted results already on most platforms,
	// but we won't rely on it for correctness beyond "stable enough".
	return m
}
