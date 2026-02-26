package instance

import (
	"time"

	"github.com/EixyScience/zmesh/internal/bench"
)

// ZMESH:ACTIVESET: expose lastSeen snapshot for bench/leader logic
func (in *Instance) LastSeenSnapshot() map[string]time.Time {
	in.mu.Lock()
	defer in.mu.Unlock()

	cp := make(map[string]time.Time, len(in.lastSeen))
	for k, v := range in.lastSeen {
		cp[k] = v
	}
	return cp
}

// ZMESH:ACTIVESET: compute active nodes set based on heartbeat (MVP)
func (in *Instance) ActiveNodes(now time.Time, window time.Duration) []string {
	seen := in.LastSeenSnapshot()
	as := bench.ActiveSet{Now: now, Window: window}

	out := make([]string, 0, len(seen))
	for node, ts := range seen {
		if as.Contains(ts) {
			out = append(out, node)
		}
	}

	// ZMESH:ACTIVESET:HOOK
	// Later: filter by bench EWMA RTT/BW/loss, role/site constraints, etc.

	return out
}
