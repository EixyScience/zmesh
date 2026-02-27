package preflight

import "time"

// Provider detects changes on mainRoot and produces a signature and (optional) diff summary.
type Provider interface {
	Name() string
	Run(now time.Time, instanceID, nodeID, stateDir, mainRoot string, excludes []string) (Result, error)
}
