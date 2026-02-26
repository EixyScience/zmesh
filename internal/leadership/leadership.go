package leadership

import (
	"sync"
	"time"

	"github.com/EixyScience/zmesh/internal/token"
)

// Role identifies a leadership function.
// ZMESH:ROLE: logistics = queue dispatch
// ZMESH:ROLE: benchmark = network metrics / active set
type Role string

const (
	RoleLogistics Role = "logistics"
	RoleBenchmark Role = "benchmark"
)

// LeaderState tracks leadership per role.
// ZMESH:LEADERSHIP:MVP single-process, backed by token.State.
type LeaderState struct {
	mu sync.Mutex

	role Role
	tok  *token.State
}

// New creates leader state bound to token state.
func New(role Role, tok *token.State) *LeaderState {
	return &LeaderState{
		role: role,
		tok:  tok,
	}
}

// Holder returns current leader node_id.
func (ls *LeaderState) Holder(now time.Time) string {
	ls.mu.Lock()
	defer ls.mu.Unlock()

	if ls.tok == nil {
		return ""
	}
	if ls.tok.HolderNodeID == "" {
		return ""
	}
	if now.After(ls.tok.ExpiresAt) {
		return ""
	}
	return ls.tok.HolderNodeID
}

// Epoch returns leadership epoch.
func (ls *LeaderState) Epoch() uint64 {
	ls.mu.Lock()
	defer ls.mu.Unlock()
	if ls.tok == nil {
		return 0
	}
	return ls.tok.Epoch
}

// IsLeader checks if node is current leader.
func (ls *LeaderState) IsLeader(now time.Time, nodeID string) bool {
	return ls.Holder(now) == nodeID
}
