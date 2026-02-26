package queue

import (
	"errors"
	"sync"
	"time"
)

var (
	ErrNotFound = errors.New("queue: not found")
	ErrConflict = errors.New("queue: conflict")
	ErrBadInput = errors.New("queue: bad input")
)

// Item is an idempotent queue element.
// ZMESH:DEDUP: EventID is the idempotency key across retries/reconcile.
type Item struct {
	EventID  string `json:"event_id"` // required (dedupe key)
	NodeID   string `json:"node_id"`  // origin node (who reported)
	TSUnixMs int64  `json:"ts_unix_ms"`

	Kind    string `json:"kind"`    // e.g. "change", "snapshot"
	Summary string `json:"summary"` // human/debug

	// Worker lease
	WorkerNodeID string `json:"worker_node_id,omitempty"`
	LeaseUntilMs int64  `json:"lease_until_ms,omitempty"`

	// Ack
	Acked     bool   `json:"acked"`
	AckBy     string `json:"ack_by,omitempty"`
	AckMsg    string `json:"ack_msg,omitempty"`
	AckUnixMs int64  `json:"ack_unix_ms,omitempty"`
	
	TokenEpoch uint64 `json:"token_epoch"` // ZMESH:FENCE: epoch fencing (required for processing)
}

type Queue struct {
	mu sync.Mutex

	order []string
	items map[string]*Item
	seen  map[string]struct{}

	lease    time.Duration
	maxItems int
}

func New(lease time.Duration) *Queue {
	if lease <= 0 {
		lease = 60 * time.Second
	}
	return &Queue{
		order:    make([]string, 0, 4096),
		items:    make(map[string]*Item, 4096),
		seen:     make(map[string]struct{}, 4096),
		lease:    lease,
		maxItems: 100000, // ZMESH:PERSIST: durable backend later
	}
}

// Enqueue inserts item if EventID not seen yet.
// ZMESH:QUEUE:MVP: in-memory queue (rebuildable)
func (q *Queue) Enqueue(it Item) (bool, error) {
	if it.EventID == "" {
		return false, ErrBadInput
	}

	q.mu.Lock()
	defer q.mu.Unlock()

	if _, ok := q.seen[it.EventID]; ok {
		return false, nil
	}

	cp := it
	q.items[it.EventID] = &cp
	q.order = append(q.order, it.EventID)
	q.seen[it.EventID] = struct{}{}

	if len(q.order) > q.maxItems {
		q.pruneLocked()
	}

	return true, nil
}

// Poll assigns leases to workerNodeID for ready items.
func (q *Queue) Poll(workerNodeID string, epoch uint64, limit int, now time.Time) ([]Item, error)
	if it.Acked {
		continue
	}
	// ZMESH:FENCE: only process items for current token epoch
	if it.TokenEpoch != epoch {
		continue
	}

	if workerNodeID == "" {
		return nil, ErrBadInput
	}
	if limit <= 0 || limit > 512 {
		limit = 64
	}

	q.mu.Lock()
	defer q.mu.Unlock()

	out := make([]Item, 0, limit)
	nowMs := now.UnixMilli()
	leaseUntil := now.Add(q.lease).UnixMilli()

	for _, eid := range q.order {
		if len(out) >= limit {
			break
		}
		it, ok := q.items[eid]
		if !ok || it.Acked {
			continue
		}
		if it.WorkerNodeID == "" || it.LeaseUntilMs <= nowMs {
			it.WorkerNodeID = workerNodeID
			it.LeaseUntilMs = leaseUntil
			out = append(out, *it)
		}
	}

	return out, nil
}

func (q *Queue) Ack(eventID string, epoch uint64, workerNodeID, msg string, now time.Time) (Item, error)
	if it.TokenEpoch != epoch {
		return *it, ErrConflict // epoch mismatch treated as conflict/fencing
	}
	
	if eventID == "" || workerNodeID == "" {
		return Item{}, ErrBadInput
	}

	q.mu.Lock()
	defer q.mu.Unlock()

	it, ok := q.items[eventID]
	if !ok {
		return Item{}, ErrNotFound
	}

	nowMs := now.UnixMilli()
	if it.WorkerNodeID != "" && it.WorkerNodeID != workerNodeID && it.LeaseUntilMs > nowMs && !it.Acked {
		return *it, ErrConflict
	}

	it.Acked = true
	it.AckBy = workerNodeID
	it.AckMsg = msg
	it.AckUnixMs = nowMs
	return *it, nil
}

func (q *Queue) pruneLocked() {
	newOrder := make([]string, 0, len(q.order))
	for _, eid := range q.order {
		it, ok := q.items[eid]
		if !ok {
			continue
		}
		if it.Acked {
			delete(q.items, eid)
			continue
		}
		newOrder = append(newOrder, eid)
	}
	q.order = newOrder
}
