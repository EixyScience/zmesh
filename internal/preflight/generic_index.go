package preflight

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type GenericIndexProvider struct{}

func (p *GenericIndexProvider) Name() string { return "generic_index" }

type fileMeta struct {
	Size    int64
	MTimeMs int64
}

func (p *GenericIndexProvider) Run(now time.Time, instanceID, nodeID, stateDir, mainRoot string, excludes []string) (Result, error) {
	res := Result{
		OK:        true,
		Message:   "ok",
		Instance:  instanceID,
		NodeID:    nodeID,
		NowUnixMs: now.UnixMilli(),

		MainChecked: true,

		Provider: p.Name(),
	}

	mainRoot = filepath.Clean(mainRoot)

	// Build current index
	curMap, curLines, err := buildIndex(mainRoot, excludes)
	if err != nil {
		res.OK = false
		res.Message = err.Error()
		return res, err
	}

	curSig := sigFromLines(curLines)
	res.MainSig = curSig

	// Load previous index & sig
	prevSig, _ := loadText(stateDir, instanceID, nodeID, "sig")
	res.PrevMainSig = strings.TrimSpace(prevSig)

	prevMap, _ := loadIndex(stateDir, instanceID, nodeID)

	// Diff
	added, modified, removed, sample := diffIndex(prevMap, curMap, 10)
	res.Added = added
	res.Modified = modified
	res.Removed = removed
	res.Sample = sample

	res.Changed = (res.PrevMainSig != "" && res.PrevMainSig != res.MainSig)

	// Save current
	if err := saveText(stateDir, instanceID, nodeID, "sig", res.MainSig+"\n"); err != nil {
		res.OK = false
		res.Message = err.Error()
		return res, err
	}
	if err := saveIndex(stateDir, instanceID, nodeID, curLines); err != nil {
		res.OK = false
		res.Message = err.Error()
		return res, err
	}

	// If changed and we can confidently say "dirty", set hint.
	// (Actual PendingSet is done by router/agent.)
	if res.Changed {
		res.PendingMaybeSet = true
	}

	return res, nil
}

func buildIndex(mainRoot string, excludes []string) (map[string]fileMeta, []string, error) {
	out := make(map[string]fileMeta, 4096)
	lines := make([]string, 0, 4096)

	// WalkDir uses OS-native enumeration. We keep it simple and portable.
	err := filepath.WalkDir(mainRoot, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			// propagate
			return err
		}
		if path == mainRoot {
			return nil
		}

		rel, rerr := filepath.Rel(mainRoot, path)
		if rerr != nil {
			return rerr
		}
		rel = filepath.ToSlash(rel)

		// Skip excluded
		if shouldSkip(rel, excludes) {
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}

		// Files only (dirs are implicit)
		if d.IsDir() {
			return nil
		}

		info, ierr := d.Info()
		if ierr != nil {
			return ierr
		}

		// We ignore symlink target content; we index the link itself as a file entry.
		// (This is OK for preflight signal. Later we can add policy knobs.)
		mt := info.ModTime().UnixMilli()
		sz := info.Size()

		out[rel] = fileMeta{Size: sz, MTimeMs: mt}
		lines = append(lines, fmt.Sprintf("%s|%d|%d", rel, sz, mt))
		return nil
	})
	if err != nil {
		return nil, nil, err
	}

	sort.Strings(lines)
	return out, lines, nil
}

func shouldSkip(rel string, excludes []string) bool {
	rel = strings.TrimPrefix(rel, "./")
	rel = strings.TrimPrefix(rel, "/")
	for _, ex := range excludes {
		ex = strings.TrimSpace(ex)
		if ex == "" {
			continue
		}
		ex = strings.TrimPrefix(ex, "./")
		ex = strings.TrimPrefix(ex, "/")
		ex = strings.TrimSuffix(ex, "/")

		// Very small glob support: "<prefix>/**"
		if strings.HasSuffix(ex, "/**") {
			prefix := strings.TrimSuffix(ex, "/**")
			if rel == prefix || strings.HasPrefix(rel, prefix+"/") {
				return true
			}
			continue
		}

		// Exact dir/file prefix
		if rel == ex || strings.HasPrefix(rel, ex+"/") {
			return true
		}
	}
	return false
}

func sigFromLines(lines []string) string {
	h := sha256.New()
	for _, ln := range lines {
		h.Write([]byte(ln))
		h.Write([]byte{'\n'})
	}
	return hex.EncodeToString(h.Sum(nil))
}

func diffIndex(prev, cur map[string]fileMeta, sampleLimit int) (added, modified, removed int, sample []string) {
	sample = make([]string, 0, sampleLimit)

	// Added/Modified
	curKeys := make([]string, 0, len(cur))
	for k := range cur {
		curKeys = append(curKeys, k)
	}
	sort.Strings(curKeys)

	for _, k := range curKeys {
		cv := cur[k]
		pv, ok := prev[k]
		if !ok {
			added++
			if len(sample) < sampleLimit {
				sample = append(sample, "+ "+k)
			}
			continue
		}
		if pv.Size != cv.Size || pv.MTimeMs != cv.MTimeMs {
			modified++
			if len(sample) < sampleLimit {
				sample = append(sample, "~ "+k)
			}
		}
	}

	// Removed
	prevKeys := make([]string, 0, len(prev))
	for k := range prev {
		prevKeys = append(prevKeys, k)
	}
	sort.Strings(prevKeys)
	for _, k := range prevKeys {
		if _, ok := cur[k]; !ok {
			removed++
			if len(sample) < sampleLimit {
				sample = append(sample, "- "+k)
			}
		}
	}
	return
}

func stateBaseDir(stateDir, instanceID, nodeID string) string {
	// Keep it flat and copyable: stateDir/preflight/<instance>/<node>.<ext>
	return filepath.Join(stateDir, "preflight", instanceID)
}

func loadText(stateDir, instanceID, nodeID, ext string) (string, error) {
	base := stateBaseDir(stateDir, instanceID, nodeID)
	path := filepath.Join(base, nodeID+"."+ext)
	b, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func saveText(stateDir, instanceID, nodeID, ext string, content string) error {
	base := stateBaseDir(stateDir, instanceID, nodeID)
	if err := os.MkdirAll(base, 0o755); err != nil {
		return err
	}
	path := filepath.Join(base, nodeID+"."+ext)
	return os.WriteFile(path, []byte(content), 0o644)
}

func loadIndex(stateDir, instanceID, nodeID string) (map[string]fileMeta, error) {
	txt, err := loadText(stateDir, instanceID, nodeID, "index")
	if err != nil {
		return map[string]fileMeta{}, err
	}
	m := make(map[string]fileMeta, 4096)
	sc := bufio.NewScanner(strings.NewReader(txt))
	for sc.Scan() {
		ln := strings.TrimSpace(sc.Text())
		if ln == "" {
			continue
		}
		// rel|size|mtime
		parts := strings.Split(ln, "|")
		if len(parts) != 3 {
			continue
		}
		rel := parts[0]
		var sz int64
		var mt int64
		_, _ = fmt.Sscanf(parts[1], "%d", &sz)
		_, _ = fmt.Sscanf(parts[2], "%d", &mt)
		m[rel] = fileMeta{Size: sz, MTimeMs: mt}
	}
	return m, nil
}

func saveIndex(stateDir, instanceID, nodeID string, lines []string) error {
	// One line per file, sorted
	var b strings.Builder
	for _, ln := range lines {
		b.WriteString(ln)
		b.WriteByte('\n')
	}
	return saveText(stateDir, instanceID, nodeID, "index", b.String())
}
