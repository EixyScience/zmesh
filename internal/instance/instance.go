package instance

import (
	"sync"
	"time"

	"github.com/EixyScience/zmesh/internal/token"
)

type EventType string

const (
	EventHeartbeat EventType = "heartbeat"
	EventToken     EventType = "token"
)

type Event struct {
	Seq      uint64    `json:"seq"`
	Type     EventType `json:"type"`
	TSUnixMs int64     `json:"ts_unix_ms"`

	// Common
	From   string `json:"from,omitempty"`
	NodeID string `json:"node_id,omitempty"`
	Site   string `json:"site,omitempty"`
	Role   string `json:"role,omitempty"`

	// Token-related
	TokenAction    string `json:"token_action,omitempty"`     // claim/renew/release/expire
	TokenHolder    string `json:"token_holder,omitempty"`     // holder after action (may be empty)
	TokenEpoch     uint64 `json:"token_epoch,omitempty"`      // epoch after action
	TokenExpiresMs int64  `json:"token_expires_ms,omitempty"` // unix ms
}

type Instance struct {
	ID string

	mu         sync.Mutex
	lastAccess time.Time
	lastSeen   map[string]time.Time
	seq        uint64
	events     []Event
	maxEvents  int

	tok token.State
}

func New(id string) *Instance {
	return &Instance{
		ID:         id,
		lastAccess: time.Now(),
		lastSeen:   make(map[string]time.Time),
		maxEvents:  4096,
	}
}

func (in *Instance) Touch() {
	in.mu.Lock()
	in.lastAccess = time.Now()
	in.mu.Unlock()
}

func (in *Instance) LastAccess() time.Time {
	in.mu.Lock()
	defer in.mu.Unlock()
	return in.lastAccess
}

func (in *Instance) RecordHeartbeat(from, nodeID, site, role string, ts time.Time) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	key := nodeID
	if key == "" {
		key = from
	}
	in.lastSeen[key] = ts

	in.seq++
	ev := Event{
		Seq:      in.seq,
		Type:     EventHeartbeat,
		TSUnixMs: ts.UnixMilli(),
		From:     from,
		NodeID:   nodeID,
		Site:     site,
		Role:     role,
	}
	in.appendEventLocked(ev)
}

// TokenStatus returns current token state, expiring it if needed.
func (in *Instance) TokenStatus(now time.Time) token.State {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	in.expireIfNeededLocked(now)
	return in.tok
}

// TokenClaim tries to claim token for nodeID.
// - If free/expired: issue new token (epoch++).
// - If already held by nodeID: renew.
// - If held by others: conflict.
func (in *Instance) TokenClaim(now time.Time, nodeID string, lease time.Duration) (token.State, error) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	in.expireIfNeededLocked(now)

	if in.tok.HolderNodeID == "" {
		in.tok.Epoch++
		in.tok.HolderNodeID = nodeID
		in.tok.IssuedAt = now
		in.tok.ExpiresAt = now.Add(lease)
		in.recordTokenEventLocked(now, "claim")
		return in.tok, nil
	}

	if in.tok.HolderNodeID == nodeID {
		in.tok.ExpiresAt = now.Add(lease)
		in.recordTokenEventLocked(now, "renew")
		return in.tok, nil
	}

	return in.tok, token.ErrConflict
}

func (in *Instance) TokenRenew(now time.Time, nodeID string, lease time.Duration) (token.State, error) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	in.expireIfNeededLocked(now)

	if in.tok.HolderNodeID == "" {
		return in.tok, token.ErrNotHeld
	}
	if in.tok.HolderNodeID != nodeID {
		return in.tok, token.ErrConflict
	}
	in.tok.ExpiresAt = now.Add(lease)
	in.recordTokenEventLocked(now, "renew")
	return in.tok, nil
}

func (in *Instance) TokenRelease(now time.Time, nodeID string) (token.State, error) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	in.expireIfNeededLocked(now)

	if in.tok.HolderNodeID == "" {
		return in.tok, nil
	}
	if in.tok.HolderNodeID != nodeID {
		return in.tok, token.ErrConflict
	}
	in.tok.HolderNodeID = ""
	in.tok.IssuedAt = time.Time{}
	in.tok.ExpiresAt = time.Time{}
	in.recordTokenEventLocked(now, "release")
	return in.tok, nil
}

func (in *Instance) Poll(afterSeq uint64, limit int) (latest uint64, out []Event) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	if limit <= 0 || limit > 512 {
		limit = 128
	}

	latest = in.seq
	for i := 0; i < len(in.events) && len(out) < limit; i++ {
		if in.events[i].Seq > afterSeq {
			out = append(out, in.events[i])
		}
	}
	return latest, out
}

func (in *Instance) expireIfNeededLocked(now time.Time) {
	if in.tok.HolderNodeID != "" && !now.Before(in.tok.ExpiresAt) {
		// expire
		in.tok.HolderNodeID = ""
		in.tok.IssuedAt = time.Time{}
		in.tok.ExpiresAt = time.Time{}
		in.recordTokenEventLocked(now, "expire")
	}
}

func (in *Instance) recordTokenEventLocked(now time.Time, action string) {
	in.seq++
	ev := Event{
		Seq:         in.seq,
		Type:        EventToken,
		TSUnixMs:    now.UnixMilli(),
		TokenAction: action,
		TokenHolder: in.tok.HolderNodeID,
		TokenEpoch:  in.tok.Epoch,
	}
	if !in.tok.ExpiresAt.IsZero() {
		ev.TokenExpiresMs = in.tok.ExpiresAt.UnixMilli()
	}
	in.appendEventLocked(ev)
}

func (in *Instance) appendEventLocked(ev Event) {
	in.events = append(in.events, ev)
	if len(in.events) > in.maxEvents {
		in.events = in.events[len(in.events)-in.maxEvents:]
	}
}
