package diffbase

import (
	"crypto/sha256"
	"encoding/hex"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type GenericIndexProvider struct{}

func (GenericIndexProvider) Name() string { return "generic_index" }

// Available expects mainRoot string (per Provider interface)
func (GenericIndexProvider) Available(mainRoot string) bool {
	if strings.TrimSpace(mainRoot) == "" {
		return false
	}
	_, err := os.Stat(mainRoot)
	return err == nil
}

func (GenericIndexProvider) Detect(req DetectRequest) (DetectResult, error) {

	if req.MainRoot == "" || req.StateDir == "" || req.InstanceID == "" || req.NodeID == "" {
		return DetectResult{
			OK:       false,
			Message:  "bad input",
			Provider: "generic_index",
		}, nil
	}
	//now := time.Now()

	// minimal validation
	if req.MainRoot == "" || req.StateDir == "" || req.InstanceID == "" || req.NodeID == "" {
		return DetectResult{OK: false, Message: "bad input", Provider: "generic_index"}, nil
	}

	if _, err := os.Stat(req.MainRoot); err != nil {
		return DetectResult{OK: false, Message: err.Error(), Provider: "generic_index"}, err
	}

	prevSig, _ := loadSig(req.StateDir, req.InstanceID, req.NodeID)

	sig, err := genericWalkSignature(req.MainRoot, req.Excludes)
	if err != nil {
		return DetectResult{OK: false, Message: err.Error(), Provider: "generic_index"}, err
	}

	changed := (prevSig != "" && sig != prevSig) || (prevSig == "" && sig != "")

	// 初回は pending を立てない方針（あなたの現状の挙動に合わせる）
	pendingMaybeSet := (prevSig != "" && sig != prevSig)

	// 保存（best effort）
	_ = saveSig(req.StateDir, req.InstanceID, req.NodeID, sig)

	return DetectResult{
		OK:              true,
		Message:         "ok",
		Provider:        "generic_index",
		MainSig:         sig,
		PrevMainSig:     prevSig,
		Changed:         changed,
		PendingMaybeSet: pendingMaybeSet,
		// NowUnixMs 等は DetectResult に無いので返さない
	}, nil
}

// genericWalkSignature returns sha256 over sorted file metadata lines.
// (path|size|mtime|mode). Does not hash file content for speed.
func genericWalkSignature(root string, excludes []string) (string, error) {
	lines := make([]string, 0, 8192)

	exNorm := make([]string, 0, len(excludes))
	for _, e := range excludes {
		e = strings.TrimSpace(e)
		if e == "" {
			continue
		}
		exNorm = append(exNorm, filepath.ToSlash(e))
	}

	shouldSkip := func(rel string) bool {
		rel = filepath.ToSlash(rel)
		for _, ex := range exNorm {
			if strings.HasSuffix(ex, "/**") {
				p := strings.TrimSuffix(ex, "/**")
				if p != "" && (rel == p || strings.HasPrefix(rel, p+"/")) {
					return true
				}
			} else {
				if rel == ex || strings.HasPrefix(rel, ex) {
					return true
				}
			}
		}
		return false
	}

	err := filepath.WalkDir(root, func(path string, d fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		rel, rerr := filepath.Rel(root, path)
		if rerr != nil {
			return rerr
		}
		if rel == "." {
			return nil
		}
		if shouldSkip(rel) {
			if d.IsDir() {
				return fs.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			return nil
		}

		info, ierr := d.Info()
		if ierr != nil {
			return ierr
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return nil
		}

		line := filepath.ToSlash(rel) +
			"|" + itoa64(info.Size()) +
			"|" + itoa64(info.ModTime().UnixNano()) +
			"|" + itoa64(int64(info.Mode()))
		lines = append(lines, line)
		return nil
	})
	if err != nil {
		return "", err
	}

	sort.Strings(lines)
	h := sha256.New()
	for _, ln := range lines {
		_, _ = h.Write([]byte(ln))
		_, _ = h.Write([]byte{'\n'})
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

func itoa64(v int64) string {
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
		b[i] = byte('0' + (v % 10))
		v /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
