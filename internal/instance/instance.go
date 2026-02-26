package instance

import (
	"sync"
	"time"
)

type EventType string

const (
	EventHeartbeat EventType = "heartbeat"
)

type Event struct {
	Seq      uint64    `json:"seq"`
	Type     EventType `json:"type"`
	TSUnixMs int64     `json:"ts_unix_ms"`
	From     string    `json:"from,omitempty"`
	NodeID   string    `json:"node_id,omitempty"`
	Site     string    `json:"site,omitempty"`
	Role     string    `json:"role,omitempty"`
}

type Instance struct {
	ID string

	mu         sync.Mutex
	lastAccess time.Time
	lastSeen   map[string]time.Time // peer/node key -> time
	seq        uint64
	events     []Event
	maxEvents  int
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
	in.events = append(in.events, ev)
	if len(in.events) > in.maxEvents {
		// keep tail
		in.events = in.events[len(in.events)-in.maxEvents:]
	}
}

func (in *Instance) Poll(afterSeq uint64, limit int) (latest uint64, out []Event) {
	in.mu.Lock()
	defer in.mu.Unlock()

	in.lastAccess = time.Now()
	if limit <= 0 || limit > 512 {
		limit = 128
	}

	latest = in.seq
	// events is already in ascending seq
	for i := 0; i < len(in.events) && len(out) < limit; i++ {
		if in.events[i].Seq > afterSeq {
			out = append(out, in.events[i])
		}
	}
	return latest, out
}
