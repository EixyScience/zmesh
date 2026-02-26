package instance

import (
	"sync"
	"time"

	"github.com/EixyScience/zmesh/internal/queue"
	"github.com/EixyScience/zmesh/internal/token"
)

type EventType string

const (
	EventHeartbeat EventType = "heartbeat"
	EventToken     EventType = "token"
	EventQueue     EventType = "queue"
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
	TokenAction    string `json:"token_action,omitempty"`
	TokenHolder    string `json:"token_holder,omitempty"`
	TokenEpoch     uint64 `json:"token_epoch,omitempty"`
	TokenExpiresMs int64  `json:"token_expires_ms,omitempty"`

	// Queue-related
	QueueAction string `json:"queue_action,omitempty"` // enqueue/poll/ack
	EventID     string `json:"event_id,omitempty"`
	Worker      string `json:"worker,omitempty"`
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
	q   *queue.Queue
}

func New(id string) *Instance {
	return &Instance{
		ID:         id,
		lastAccess: time.Now(),
		lastSeen:   make(map[string]time.Time),
		maxEvents:  4096,
		q:          queue.New(60 * time.Second),
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

// ---------------- Token ----------------

func (in *Instance) TokenStatus(now time.Time) token.State {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	in.expireIfNeededLocked(now)
	return in.tok
}

// ZMESH:TOKEN: per-scalefs lease-based mutual exclusion.
// ZMESH:EXTEND: replace issuer with distributed consensus when orchestration layer exists.
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

func (in *Instance) expireIfNeededLocked(now time.Time) {
	if in.tok.HolderNodeID != "" && !now.Before(in.tok.ExpiresAt) {
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

	// ZMESH:RECOVERY: token epoch change is a natural point to run reconcile (queue rebuild)
	// ZMESH:HOOK: governor takeover should query pending changes from all nodes here.
}

// ---------------- Queue ----------------

// ZMESH:QUEUE:MVP: in-memory queue, rebuildable via reconcile.
// ZMESH:DEDUP: event_id must be stable across retries.
func (in *Instance) QueueEnqueue(it queue.Item) (bool, error) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	inserted, err := in.q.Enqueue(it)
	if err != nil {
		return false, err
	}
	if inserted {
		in.seq++
		in.appendEventLocked(Event{
			Seq:         in.seq,
			Type:        EventQueue,
			TSUnixMs:    time.Now().UnixMilli(),
			QueueAction: "enqueue",
			EventID:     it.EventID,
			NodeID:      it.NodeID,
		})
	}
	return inserted, nil
}

func (in *Instance) QueuePoll(workerNodeID string, limit int, now time.Time) ([]queue.Item, error) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	items, err := in.q.Poll(workerNodeID, limit, now)
	if err == nil && len(items) > 0 {
		in.seq++
		in.appendEventLocked(Event{
			Seq:         in.seq,
			Type:        EventQueue,
			TSUnixMs:    now.UnixMilli(),
			QueueAction: "poll",
			Worker:      workerNodeID,
		})
	}
	return items, err
}

func (in *Instance) QueueAck(eventID, workerNodeID, msg string, now time.Time) (queue.Item, error) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	it, err := in.q.Ack(eventID, workerNodeID, msg, now)
	if err == nil {
		in.seq++
		in.appendEventLocked(Event{
			Seq:         in.seq,
			Type:        EventQueue,
			TSUnixMs:    now.UnixMilli(),
			QueueAction: "ack",
			EventID:     eventID,
			Worker:      workerNodeID,
		})
	}
	return it, err
}

// ---------------- Poll events ----------------

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

func (in *Instance) appendEventLocked(ev Event) {
	in.events = append(in.events, ev)
	if len(in.events) > in.maxEvents {
		in.events = in.events[len(in.events)-in.maxEvents:]
	}
}
