// diff provider として独立させます
package generic

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/EixyScience/zmesh/internal/diffbase"
)

type Provider struct{}

func New() *Provider { return &Provider{} }

func (p *Provider) Name() string { return "generic_index" }

func (p *Provider) Available(root string) bool { return true }

func (p *Provider) Detect(req diffbase.DetectRequest) (diffbase.DetectResult, error) {
	// mainRoot existence
	if st, err := os.Stat(req.MainRoot); err != nil || !st.IsDir() {
		if err == nil {
			err = errors.New("mainRoot is not a directory")
		}
		return diffbase.DetectResult{OK: false, Message: err.Error(), Provider: p.Name()}, err
	}

	_ = os.MkdirAll(req.StateDir, 0o755)

	prevPath := filepath.Join(req.StateDir, "main.sig")
	prevSig := readText(prevPath)

	sig, err := computeTreeSig(req.MainRoot, req.Excludes)
	if err != nil {
		return diffbase.DetectResult{OK: false, Message: err.Error(), Provider: p.Name()}, err
	}

	changed := (prevSig != "" && sig != prevSig)

	// 初回は prevSig="" なので changed=false 扱い（必要なら後で policy 変更可能）
	if prevSig == "" {
		changed = false
	}

	_ = os.WriteFile(prevPath, []byte(sig+"\n"), 0o644)

	return diffbase.DetectResult{
		OK:      true,
		Message: "ok",

		Changed: changed,

		MainSig:     sig,
		PrevMainSig: strings.TrimSpace(prevSig),

		Provider: p.Name(),

		PendingMaybeSet: changed,
	}, nil
}

func computeTreeSig(root string, excludes []string) (string, error) {
	m := diffbase.NewMatcher(excludes)

	type entry struct {
		rel  string
		hash string
		mode os.FileMode
		size int64
	}

	ents := make([]entry, 0, 4096)

	err := filepath.WalkDir(root, func(path string, d os.DirEntry, err error) error {
		if err != nil {
			return err
		}

		rel, ok := diffbase.CleanRel(root, path)
		if !ok {
			return nil
		}
		// root 自身は対象外（空文字）
		if rel == "" {
			return nil
		}

		// exclude
		if m.MatchRel(rel) {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}

		info, e := d.Info()
		if e != nil {
			return e
		}

		if info.IsDir() {
			// dir はマーカーだけ入れる（構造変化検出用）
			ents = append(ents, entry{rel: rel + "/", hash: "DIR", mode: info.Mode()})
			return nil
		}

		// symlink はリンク先文字列をハッシュ
		if info.Mode()&os.ModeSymlink != 0 {
			target, _ := os.Readlink(path)
			h := sha256.Sum256([]byte("LNK:" + target))
			ents = append(ents, entry{
				rel:  rel,
				hash: hex.EncodeToString(h[:]),
				mode: info.Mode(),
				size: int64(len(target)),
			})
			return nil
		}

		// regular file only
		if !info.Mode().IsRegular() {
			// デバイス等は marker
			h := sha256.Sum256([]byte("SPECIAL"))
			ents = append(ents, entry{rel: rel, hash: hex.EncodeToString(h[:]), mode: info.Mode()})
			return nil
		}

		f, e := os.Open(path)
		if e != nil {
			return e
		}
		defer f.Close()

		hasher := sha256.New()
		if _, e := io.Copy(hasher, f); e != nil {
			return e
		}
		sum := hex.EncodeToString(hasher.Sum(nil))

		ents = append(ents, entry{
			rel:  rel,
			hash: sum,
			mode: info.Mode(),
			size: info.Size(),
		})
		return nil
	})

	if err != nil {
		return "", err
	}

	sort.Slice(ents, func(i, j int) bool { return ents[i].rel < ents[j].rel })

	// Tree signature
	tree := sha256.New()
	for _, e := range ents {
		// rel|mode|size|hash
		line := e.rel + "|" + e.mode.String() + "|" + itoa64(e.size) + "|" + e.hash + "\n"
		_, _ = tree.Write([]byte(line))
	}
	return hex.EncodeToString(tree.Sum(nil)), nil
}

func readText(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func itoa64(v int64) string {
	// fmt は遅いので簡易
	neg := v < 0
	if neg {
		v = -v
	}
	var buf [32]byte
	i := len(buf)
	if v == 0 {
		i--
		buf[i] = '0'
	} else {
		for v > 0 {
			i--
			buf[i] = byte('0' + (v % 10))
			v /= 10
		}
	}
	if neg {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}
