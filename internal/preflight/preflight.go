package preflight

import (
	"os"
	"path/filepath"
	"strings"
	"time"
)

// ZMESH:PREFLIGHT:MVP
// This is intentionally conservative and mostly "hooks".
// The goal is to ensure we don't lose local changes made before zmesh start.

type Result struct {
	OK        bool   `json:"ok"`
	Message   string `json:"message"`
	Instance  string `json:"instance"`
	NodeID    string `json:"node_id"`
	NowUnixMs int64  `json:"now_unix_ms"`

	MainChecked     bool `json:"main_checked"`
	ShadowPrepared  bool `json:"shadow_prepared"`
	JournalPrepared bool `json:"journal_prepared"`
	PendingMaybeSet bool `json:"pending_maybe_set"`

	MainSig     string `json:"main_sig"`
	PrevMainSig string `json:"prev_main_sig"`
	Changed     bool   `json:"changed"`

	// 追加：どの検出方式か
	Provider string `json:"provider,omitempty"`

	// 追加：差分サマリ
	Added    int      `json:"added,omitempty"`
	Modified int      `json:"modified,omitempty"`
	Removed  int      `json:"removed,omitempty"`
	Sample   []string `json:"sample,omitempty"`
}

type Runner struct{}

type Preflight struct {
	providers []Provider
}

func New() *Preflight {
	// 優先順位：ZFS（将来）→Generic
	return &Preflight{
		providers: []Provider{
			// TODO: ZFSProvider をここに挿す（datasetが分かるようになったら）
			&GenericIndexProvider{},
		},
	}
}

func (p *Preflight) Run(instanceID, nodeID, stateDir, mainRoot string, excludes []string) Result {
	now := time.Now()

	// Providerを順に試す。今回は必ずGenericが成功する想定。
	for _, pr := range p.providers {
		res, err := pr.Run(now, instanceID, nodeID, stateDir, mainRoot, excludes)
		if err == nil && res.OK {
			return res
		}
		// 失敗したら次のproviderへ（将来ZFSが落ちた時にフォールバックさせる）
	}
	return Result{
		OK:        false,
		Message:   "no provider succeeded",
		Instance:  instanceID,
		NodeID:    nodeID,
		NowUnixMs: now.UnixMilli(),
	}
}

func sigPath(stateDir, instanceID, nodeID string) string {
	return filepath.Join(stateDir, "preflight", instanceID, nodeID+".sig")
}

func loadSig(stateDir, instanceID, nodeID string) (string, error) {
	fp := sigPath(stateDir, instanceID, nodeID)
	b, err := os.ReadFile(fp)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func saveSig(stateDir, instanceID, nodeID, sig string) error {
	fp := sigPath(stateDir, instanceID, nodeID)
	if err := os.MkdirAll(filepath.Dir(fp), 0o755); err != nil {
		return err
	}
	tmp := fp + ".tmp"
	if err := os.WriteFile(tmp, []byte(sig+"\n"), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, fp)
}
