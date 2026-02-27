package preflight

import (
	"crypto/sha256"
	"encoding/hex"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

// ZMESH:PREFLIGHT:SCAN:MVP
// Portable signature (path+size+mtime) for main tree.
// This is not cryptographic integrity, just change detection.

type ScanConfig struct {
	Root         string   // main root directory
	ExcludeGlobs []string // relative to Root
	MaxFiles     int      // safety
	Now          time.Time
}

type ScanResult struct {
	Root      string `json:"root"`
	FileCnt   int    `json:"file_count"`
	Sig       string `json:"sig"`
	NowUnixMs int64  `json:"now_unix_ms"`
}

func ScanTree(cfg ScanConfig) (ScanResult, error) {
	if cfg.MaxFiles <= 0 {
		cfg.MaxFiles = 200000
	}
	if cfg.Now.IsZero() {
		cfg.Now = time.Now()
	}
	root := cfg.Root
	if root == "" {
		root = "."
	}

	var lines []string
	count := 0

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// best effort: skip unreadable paths
			return nil
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return nil
		}
		rel = filepath.ToSlash(rel)
		if rel == "." || rel == "" {
			return nil
		}

		// exclude?
		for _, g := range cfg.ExcludeGlobs {
			g = strings.TrimSpace(g)
			if g == "" {
				continue
			}
			gg := filepath.ToSlash(g)
			if ok, _ := filepath.Match(gg, rel); ok {
				return nil
			}
		}

		info, err := os.Stat(path)
		if err != nil {
			return nil
		}
		// path|size|mtimeUnix
		lines = append(lines, rel+"|"+itoa64(info.Size())+"|"+itoa64(info.ModTime().Unix()))
		count++
		if count >= cfg.MaxFiles {
			return fs.SkipAll
		}
		return nil
	})
	if err != nil {
		return ScanResult{}, err
	}

	sort.Strings(lines)
	h := sha256.New()
	for _, ln := range lines {
		h.Write([]byte(ln))
		h.Write([]byte{'\n'})
	}
	sum := hex.EncodeToString(h.Sum(nil))

	return ScanResult{
		Root:      root,
		FileCnt:   count,
		Sig:       sum,
		NowUnixMs: cfg.Now.UnixMilli(),
	}, nil
}

func itoa64(v int64) string {
	// fast enough for MVP
	return strconvFormatInt(v)
}

// avoid importing strconv in multiple files if you prefer; simplest:
func strconvFormatInt(v int64) string {
	// local minimal conversion
	if v == 0 {
		return "0"
	}
	neg := v < 0
	if neg {
		v = -v
	}
	var b [32]byte
	i := len(b)
	for v > 0 {
		i--
		b[i] = byte('0' + v%10)
		v /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
