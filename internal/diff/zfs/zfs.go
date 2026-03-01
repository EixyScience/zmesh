// 権限不足や zfs 不在なら 自動的に generic にフォールバックします
package zfs

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/EixyScience/zmesh/internal/diffbase"
)

type Provider struct{}

func New() *Provider { return &Provider{} }

func (p *Provider) Name() string { return "zfs" }

func (p *Provider) Available(root string) bool {
	_, err := exec.LookPath("zfs")
	if err != nil {
		return false
	}

	// root が存在しないなら不可
	st, err := os.Stat(root)
	if err != nil || !st.IsDir() {
		return false
	}

	// dataset 判定できないなら不可（=フォールバックさせる）
	_, _, err = findDatasetForPath(root)
	return err == nil
}

func (p *Provider) Detect(req diffbase.DetectRequest) (diffbase.DetectResult, error) {
	ds, mp, err := findDatasetForPath(req.MainRoot)
	if err != nil {
		return diffbase.DetectResult{OK: false, Message: err.Error(), Provider: p.Name()}, err
	}

	_ = os.MkdirAll(req.StateDir, 0o755)

	lastPath := filepath.Join(req.StateDir, "zfs.lastsnap")
	prevSnap := readText(lastPath)

	// 新 snapshot 名（node/instance を混ぜて衝突回避）
	tag := fmt.Sprintf("zmesh_%s_%s_%d", sanitize(req.InstanceID), sanitize(req.NodeID), time.Now().Unix())
	newSnap := ds + "@" + tag

	// snapshot 作成（失敗ならフォールバック）
	if err := zfsSnapshot(newSnap); err != nil {
		return diffbase.DetectResult{OK: false, Message: "zfs snapshot failed: " + err.Error(), Provider: p.Name()}, err
	}

	// 初回: prev が無いなら changed=false で登録して終わり
	if prevSnap == "" {
		_ = os.WriteFile(lastPath, []byte(newSnap+"\n"), 0o644)
		return diffbase.DetectResult{
			OK:      true,
			Message: "ok",
			Changed: false,

			MainSig:     newSnap,
			PrevMainSig: "",

			Provider: p.Name(),

			PendingMaybeSet: false,
		}, nil
	}

	// zfs diff
	changed, derr := zfsDiffChanged(prevSnap, newSnap, mp, req.MainRoot, req.Excludes)

	// 古い snapshot は削除（失敗しても致命ではない）
	_ = zfsDestroy(prevSnap)

	_ = os.WriteFile(lastPath, []byte(newSnap+"\n"), 0o644)

	if derr != nil {
		// diff 失敗時も provider 失敗扱いにしてフォールバックを許可
		return diffbase.DetectResult{OK: false, Message: "zfs diff failed: " + derr.Error(), Provider: p.Name()}, derr
	}

	return diffbase.DetectResult{
		OK:      true,
		Message: "ok",

		Changed: changed,

		MainSig:     newSnap,
		PrevMainSig: prevSnap,

		Provider: p.Name(),

		PendingMaybeSet: changed,
	}, nil
}

func findDatasetForPath(path string) (dataset string, mountpoint string, err error) {
	// zfs list -H -o name,mountpoint
	out, err := exec.Command("zfs", "list", "-H", "-o", "name,mountpoint").CombinedOutput()
	if err != nil {
		return "", "", fmt.Errorf("zfs list failed: %w: %s", err, string(out))
	}

	abs, err := filepath.Abs(path)
	if err != nil {
		return "", "", err
	}

	bestLen := -1
	var bestDS, bestMP string

	lines := strings.Split(string(out), "\n")
	for _, ln := range lines {
		ln = strings.TrimSpace(ln)
		if ln == "" {
			continue
		}
		parts := strings.SplitN(ln, "\t", 2)
		if len(parts) != 2 {
			continue
		}
		ds := strings.TrimSpace(parts[0])
		mp := strings.TrimSpace(parts[1])
		if mp == "" || mp == "-" || mp == "legacy" {
			continue
		}

		mpAbs, e := filepath.Abs(mp)
		if e != nil {
			continue
		}

		rel, e := filepath.Rel(mpAbs, abs)
		if e != nil {
			continue
		}
		if strings.HasPrefix(rel, "..") {
			continue
		}

		// longest prefix match
		if len(mpAbs) > bestLen {
			bestLen = len(mpAbs)
			bestDS = ds
			bestMP = mpAbs
		}
	}

	if bestLen < 0 {
		return "", "", errors.New("path is not on ZFS mountpoint")
	}
	return bestDS, bestMP, nil
}

func zfsSnapshot(fullSnap string) error {
	out, err := exec.Command("zfs", "snapshot", fullSnap).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, string(out))
	}
	return nil
}

func zfsDestroy(fullSnap string) error {
	out, err := exec.Command("zfs", "destroy", fullSnap).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, string(out))
	}
	return nil
}

func zfsDiffChanged(oldSnap, newSnap, mountpointAbs, mainRoot string, excludes []string) (bool, error) {
	// zfs diff -FH old new
	// 出力例: "M\t/path/to/file"
	out, err := exec.Command("zfs", "diff", "-F", "-H", oldSnap, newSnap).CombinedOutput()
	if err != nil {
		return false, fmt.Errorf("%w: %s", err, string(out))
	}

	m := diffbase.NewMatcher(excludes)

	mainAbs, _ := filepath.Abs(mainRoot)

	lines := bytes.Split(out, []byte{'\n'})
	for _, ln := range lines {
		ln = bytes.TrimSpace(ln)
		if len(ln) == 0 {
			continue
		}

		// format: <op>\t<path>
		parts := bytes.SplitN(ln, []byte{'\t'}, 3)
		if len(parts) < 2 {
			continue
		}

		p := strings.TrimSpace(string(parts[1]))
		if p == "" {
			continue
		}

		// mainRoot 配下だけを見る（dataset全体ではなく watch_root のみ）
		pAbs, e := filepath.Abs(p)
		if e != nil {
			continue
		}
		relToMain, ok := diffbase.CleanRel(mainAbs, pAbs)
		if !ok {
			continue
		}

		// exclude
		if m.MatchRel(relToMain) {
			continue
		}

		// 何か1つでも差分があれば changed=true
		return true, nil
	}

	return false, nil
}

func readText(path string) string {
	b, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(b))
}

func sanitize(s string) string {
	s = strings.TrimSpace(s)
	s = strings.ReplaceAll(s, ":", "_")
	s = strings.ReplaceAll(s, "/", "_")
	s = strings.ReplaceAll(s, "\\", "_")
	if s == "" {
		return "x"
	}
	return s
}
