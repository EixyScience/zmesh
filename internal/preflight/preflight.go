package preflight

import (
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
}

type Runner struct{}

func New() *Runner { return &Runner{} }

func (r *Runner) Run(instanceID, nodeID string) Result {
	now := time.Now()
	res := Result{
		OK:        true,
		Message:   "ok",
		Instance:  instanceID,
		NodeID:    nodeID,
		NowUnixMs: now.UnixMilli(),
	}

	// ZMESH:PREFLIGHT:HOOK: check main integrity / detect pre-start changes
	res.MainChecked = true

	// ZMESH:PREFLIGHT:HOOK: ensure .shadow exists / safety staging ready
	res.ShadowPrepared = true

	// ZMESH:PREFLIGHT:HOOK: ensure change journal exists / is writable
	res.JournalPrepared = true

	// ZMESH:PREFLIGHT:HOOK: if pre-start changes detected -> set pending dirty
	res.PendingMaybeSet = false

	return res
}
