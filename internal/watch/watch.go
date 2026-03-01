package watch

import (
	"path/filepath"
	"strings"
)

// ZMESH:WATCH: main-only default + hard excludes for internal clones.
// The caller should pass paths relative to the filesystem root being watched.

type Config struct {
	// Root is the watched root path (e.g., /scalefs/main)
	Root string

	// ExcludeGlobs are optional user-configured patterns (filepath.Match style).
	// Examples: ".zmesh/**", "zmesh.state/**", "*.swp"
	ExcludeGlobs []string
}

// IsExcluded returns true if relPath should be ignored by sensors.
// relPath must be path relative to Config.Root, using OS path separators.
func (c Config) IsExcluded(relPath string) bool {
	p := filepath.Clean(relPath)

	// ZMESH:WATCH: hard excludes (internal working trees)
	// Exclude anything under these directories if they appear in the path.
	// Note: we normalize separators and use a contains check on path segments.
	seg := splitPathSegments(p)
	for _, s := range seg {
		switch s {
		case ".shadow", ".latest", ".tmp":
			return true
		}
	}

	// User excludes
	for _, g := range c.ExcludeGlobs {
		g = strings.TrimSpace(g)
		if g == "" {
			continue
		}
		if ok, _ := filepath.Match(g, p); ok {
			return true
		}
		// Also try matching with forward slashes to make configs portable.
		pp := filepath.ToSlash(p)
		gg := filepath.ToSlash(g)
		if ok, _ := filepath.Match(gg, pp); ok {
			return true
		}
	}

	return false
}

func splitPathSegments(p string) []string {
	p = filepath.ToSlash(p)
	p = strings.TrimPrefix(p, "./")
	p = strings.TrimPrefix(p, "/")
	if p == "" {
		return nil
	}
	return strings.Split(p, "/")
}
