package preflight

import (
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/EixyScience/zmesh/internal/diff"
	"github.com/EixyScience/zmesh/internal/diffbase"
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

type Preflight struct{}

func New() *Preflight { return &Preflight{} }

//func New() *Runner { return &Runner{} }

func (p *Preflight) Run(instanceID, nodeID, stateDir, mainRoot string, excludes []string) Result {
	now := time.Now()

	dr, err := diff.Detect(diffbase.DetectRequest{
		InstanceID: instanceID,
		NodeID:     nodeID,
		MainRoot:   mainRoot,
		StateDir:   stateDir,
		Excludes:   excludes,
	})
	if err != nil || !dr.OK {
		msg := "no provider succeeded"
		if dr.Message != "" {
			msg = dr.Message
		} else if err != nil {
			msg = err.Error()
		}
		return Result{
			OK:        false,
			Message:   msg,
			Instance:  instanceID,
			NodeID:    nodeID,
			NowUnixMs: now.UnixMilli(),

			MainChecked:     false,
			ShadowPrepared:  false,
			JournalPrepared: false,

			PendingMaybeSet: false,
			Changed:         false,
			Provider:        dr.Provider,
		}
	}

	return Result{
		OK:        true,
		Message:   "ok",
		Instance:  instanceID,
		NodeID:    nodeID,
		NowUnixMs: now.UnixMilli(),

		MainChecked:     true,
		ShadowPrepared:  false, // ZMESH:TODO: next phase
		JournalPrepared: false, // ZMESH:TODO: next phase

		PendingMaybeSet: dr.PendingMaybeSet,

		MainSig:     dr.MainSig,
		PrevMainSig: dr.PrevMainSig,

		Changed:  dr.Changed,
		Provider: dr.Provider,
	}

	/*
	   	for _, pr := range p.providers {
	   		//res, err := pr.Run(now, instanceID, nodeID, stateDir, mainRoot, excludes)
	   		res, err := diffbase.Detect(diff.DetectRequest{
	   			InstanceID: in.ID,
	   			NodeID:     nid,

	   			MainRoot: mainRoot,
	   			StateDir: stateDir,
	   			Excludes: excludes,
	   		})
	   		if err == nil && res.OK {
	   			return res
	   		}
	   		if err != nil {
	   			lastErr = err
	   		} else if !res.OK && res.Message != "" {
	   			lastErr = errors.New(res.Message)
	   		}
	   	}

	   msg := "no provider succeeded"

	   	if lastErr != nil {
	   		msg = msg + ": " + lastErr.Error()
	   	}

	   	return Result{
	   		OK:        false,
	   		Message:   msg,
	   		Instance:  instanceID,
	   		NodeID:    nodeID,
	   		NowUnixMs: now.UnixMilli(),
	   	}
	*/
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
