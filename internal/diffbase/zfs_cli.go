package diffbase

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"time"
)

type zfsCLIProvider struct{}

// ZMESH:DIFF:ZFS: best-effort; actual Detect() may still fail if not on ZFS.
// Available returns true if zfs CLI exists in PATH.
func (zfsCLIProvider) Available(_ string) bool {
	_, err := exec.LookPath("zfs")
	return err == nil
}

func (z zfsCLIProvider) Name() string { return "zfs_cli" }

func (z zfsCLIProvider) Detect(req DetectRequest) (DetectResult, error) {
	// Windows では ZFS CLI 期待しない
	if runtime.GOOS == "windows" {
		return DetectResult{OK: false, Message: "zfs not supported on windows"}, nil
	}

	main := filepath.Clean(req.MainRoot)
	if main == "" {
		return DetectResult{OK: false, Message: "main_root empty"}, nil
	}

	// 1) mountpoint -> dataset を推定（zfs list -H -o name,mountpoint）
	ds, mp, err := z.findDatasetForPath(req, main)
	if err != nil || ds == "" {
		// 権限不足/コマンドなし/非ZFS いずれもフォールバック
		msg := "zfs dataset not found"
		if err != nil {
			msg = err.Error()
		}
		return DetectResult{OK: false, Message: msg}, nil
	}

	// 2) dataset の "変化検知に使える属性" を取得（読み取りだけで済む）
	props, err := z.getDatasetProps(req, ds)
	if err != nil {
		return DetectResult{OK: false, Message: err.Error()}, nil
	}

	// 3) props を署名化（高速）
	// ZMESH:DIFF:ZFS:MVP: 将来は zfs diff/snapshot ベースの Added/Modified/Removed を付ける
	sum := sha256.Sum256([]byte(ds + "\n" + mp + "\n" + props))
	mainSig := hex.EncodeToString(sum[:])

	prev, _ := loadSig(req.StateDir, req.InstanceID, req.NodeID)
	changed := (prev != "" && prev != mainSig)

	// 初回でも prev=="" のときは changed=false にしている（いまの generic と揃える）
	_ = saveSig(req.StateDir, req.InstanceID, req.NodeID, mainSig)

	return DetectResult{
		OK:              true,
		Message:         "ok",
		MainSig:         mainSig,
		PrevMainSig:     prev,
		Changed:         changed,
		PendingMaybeSet: changed || prev == "",
	}, nil
}

func (z zfsCLIProvider) findDatasetForPath(req DetectRequest, path string) (dataset string, mountpoint string, err error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// zfs list -H -o name,mountpoint
	out, err := runCmd(ctx, "zfs", "list", "-H", "-o", "name,mountpoint")
	if err != nil {
		return "", "", err
	}

	abs := path
	// path が相対なら、呼び出し側が絶対化するのが理想だが、念のためここでも吸収
	if !filepath.IsAbs(abs) {
		abs, _ = filepath.Abs(abs)
	}
	abs = filepath.Clean(abs)

	bestLen := -1
	var bestDS, bestMP string

	lines := strings.Split(out, "\n")
	for _, ln := range lines {
		ln = strings.TrimSpace(ln)
		if ln == "" {
			continue
		}
		// name<TAB>mountpoint
		parts := strings.Split(ln, "\t")
		if len(parts) < 2 {
			parts = strings.Fields(ln)
		}
		if len(parts) < 2 {
			continue
		}
		ds := strings.TrimSpace(parts[0])
		mp := strings.TrimSpace(parts[1])
		if ds == "" || mp == "" || mp == "-" {
			continue
		}

		mpClean := filepath.Clean(mp)
		// abs が mp の配下か？
		if abs == mpClean || strings.HasPrefix(abs, mpClean+string(filepath.Separator)) {
			if len(mpClean) > bestLen {
				bestLen = len(mpClean)
				bestDS, bestMP = ds, mpClean
			}
		}
	}

	return bestDS, bestMP, nil
}

func (z zfsCLIProvider) getDatasetProps(req DetectRequest, ds string) (string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	// 変化検知に効く情報を軽く集める
	// written は増減するので「変更があった」には強い。ない環境もあるので fallback 可能なセットにする。
	// guid は dataset 固有（不変寄り）。mountpoint は上で取っている。
	// volsize 等は dataset により変わるので環境依存に注意。
	// ZMESH:DIFF:ZFS:PROPS: 必要なら調整
	out, err := runCmd(ctx, "zfs", "get", "-H", "-p", "-o", "property,value", "written,used,refer,available,guid", ds)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(out), nil
}

func runCmd(ctx context.Context, name string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err != nil {
		// 権限不足・コマンド無しもここに来る。上位で静かにフォールバックする。
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", execError{name: name, msg: msg}
	}
	return stdout.String(), nil
}

type execError struct {
	name string
	msg  string
}

func (e execError) Error() string { return e.name + ": " + e.msg }
