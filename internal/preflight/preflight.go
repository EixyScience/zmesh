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
	OK      bool   `json:"ok"`
	Message string `json:"message"`

	Instance string `json:"instance"`
	NodeID   string `json:"node_id"`

	NowUnixMs int64 `json:"now_unix_ms"`

	// Hooks / future metrics
	MainChecked     bool `json:"main_checked"`
	ShadowPrepared  bool `json:"shadow_prepared"`
	JournalPrepared bool `json:"journal_prepared"`
	PendingMaybeSet bool `json:"pending_maybe_set"`

	MainSig     string `json:"main_sig"`
	PrevMainSig string `json:"prev_main_sig"`
	Changed     bool   `json:"changed"`
}

type Runner struct{}

func New() *Runner { return &Runner{} }

func (r *Runner) Run(instanceID, nodeID, stateDir, mainRoot string, exclude []string) Result {
	now := time.Now()
	res := Result{
		OK:        true,
		Message:   "ok",
		Instance:  instanceID,
		NodeID:    nodeID,
		NowUnixMs: now.UnixMilli(),
	}

	res.MainChecked = true

	// compute current signature
	sr, err := ScanTree(ScanConfig{
		Root:         mainRoot,
		ExcludeGlobs: exclude,
		Now:          now,
	})
	if err != nil {
		res.OK = false
		res.Message = "scan failed: " + err.Error()
		return res
	}
	res.MainSig = sr.Sig

	// load previous signature
	prev, _ := loadSig(stateDir, instanceID, nodeID)
	res.PrevMainSig = prev
	res.Changed = (prev != "" && prev != sr.Sig)

	// save signature for next boot
	_ = saveSig(stateDir, instanceID, nodeID, sr.Sig)

	res.ShadowPrepared = true
	res.JournalPrepared = true

	// If changed, caller should set pending dirty (hook; we return flag)
	res.PendingMaybeSet = res.Changed

	return res
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
