package diffbase

import (
	"path/filepath"
	"regexp"
	"runtime"
	"strings"
)

type Matcher struct {
	re []*regexp.Regexp
}

func NewMatcher(patterns []string) *Matcher {
	m := &Matcher{}
	for _, p := range patterns {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		p = strings.ReplaceAll(p, "\\", "/")
		re := globToRegexp(p)
		m.re = append(m.re, re)
	}
	return m
}

func (m *Matcher) MatchRel(rel string) bool {
	rel = strings.ReplaceAll(rel, "\\", "/")
	if runtime.GOOS == "windows" {
		rel = strings.ToLower(rel)
	}
	for _, r := range m.re {
		if r.MatchString(rel) {
			return true
		}
	}
	return false
}

func CleanRel(base, path string) (string, bool) {
	absBase, err1 := filepath.Abs(base)
	absPath, err2 := filepath.Abs(path)
	if err1 != nil || err2 != nil {
		return "", false
	}
	rel, err := filepath.Rel(absBase, absPath)
	if err != nil {
		return "", false
	}
	rel = filepath.ToSlash(rel)
	if strings.HasPrefix(rel, "../") || rel == ".." {
		return "", false
	}
	return rel, true
}

func globToRegexp(glob string) *regexp.Regexp {
	var b strings.Builder
	b.WriteString("^")

	for i := 0; i < len(glob); i++ {
		c := glob[i]
		if c == '*' {
			if i+1 < len(glob) && glob[i+1] == '*' {
				b.WriteString(".*")
				i++
				continue
			}
			b.WriteString(`[^/]*`)
			continue
		}
		if c == '?' {
			b.WriteString(`[^/]`)
			continue
		}
		if strings.ContainsRune(`.+()|[]{}^$\/`, rune(c)) {
			b.WriteByte('\\')
		}
		b.WriteByte(c)
	}

	b.WriteString("$")

	s := b.String()
	if runtime.GOOS == "windows" {
		s = "(?i)" + s
	}
	return regexp.MustCompile(s)
}
