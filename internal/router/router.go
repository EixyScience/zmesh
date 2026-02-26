package router

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/EixyScience/zmesh/internal/id"
	"github.com/EixyScience/zmesh/internal/instance"
	"github.com/EixyScience/zmesh/internal/pending"
	"github.com/EixyScience/zmesh/internal/queue"
	"github.com/EixyScience/zmesh/internal/reconcile"
	"github.com/EixyScience/zmesh/internal/token"
)

type Registry struct {
	mu       sync.Mutex
	items    map[string]*instance.Instance
	ttl      time.Duration
	janitorI time.Duration
}

type reconcileReply struct {
	OK       bool   `json:"ok"`
	Message  string `json:"message"`
	Instance string `json:"instance"`

	Peers       []string `json:"peers"`
	PulledItems int      `json:"pulled_items"`
	EnqueuedNew int      `json:"enqueued_new"`
}

func NewRegistry(ttl time.Duration) *Registry {
	return &Registry{
		items:    make(map[string]*instance.Instance),
		ttl:      ttl,
		janitorI: 30 * time.Second,
	}
}

func (r *Registry) GetOrCreate(instanceID string) (*instance.Instance, error) {
	if err := id.ValidateUUID(instanceID); err != nil {
		return nil, err
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	if in, ok := r.items[instanceID]; ok {
		in.Touch()
		return in, nil
	}
	in := instance.New(instanceID)
	r.items[instanceID] = in
	return in, nil
}

func (r *Registry) RunJanitor(ctx context.Context) {
	t := time.NewTicker(r.janitorI)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			r.sweep()
		}
	}
}

func (r *Registry) sweep() {
	if r.ttl <= 0 {
		return
	}
	now := time.Now()
	r.mu.Lock()
	defer r.mu.Unlock()
	for k, in := range r.items {
		if now.Sub(in.LastAccess()) > r.ttl {
			delete(r.items, k)
		}
	}
}

type Router struct {
	reg *Registry

	tokenLease time.Duration
}

func New(reg *Registry) *Router {
	return &Router{
		reg:        reg,
		tokenLease: 30 * time.Second,
	}
}

type pingReply struct {
	OK      bool   `json:"ok"`
	Message string `json:"message"`
}

type hbReq struct {
	NodeID string `json:"node_id"`
	Site   string `json:"site"`
	Role   string `json:"role"`
	TSUnix int64  `json:"ts_unix"`
}

type pollReply struct {
	OK       bool             `json:"ok"`
	Latest   uint64           `json:"latest"`
	Events   []instance.Event `json:"events"`
	Instance string           `json:"instance"`
}

type tokenStatusReply struct {
	OK       bool        `json:"ok"`
	Instance string      `json:"instance"`
	Token    token.State `json:"token"`
	NowUnix  int64       `json:"now_unix"`
}

type tokenActionReq struct {
	NodeID string `json:"node_id"`
}

type tokenActionReply struct {
	OK       bool        `json:"ok"`
	Message  string      `json:"message"`
	Instance string      `json:"instance"`
	Token    token.State `json:"token"`
	NowUnix  int64       `json:"now_unix"`
}

type queueEnqReply struct {
	OK       bool   `json:"ok"`
	Message  string `json:"message"`
	Instance string `json:"instance"`
	Inserted bool   `json:"inserted"`
}

type queuePollReply struct {
	OK       bool         `json:"ok"`
	Message  string       `json:"message"`
	Instance string       `json:"instance"`
	Items    []queue.Item `json:"items"`
}

type queueAckReq struct {
	EventID      string `json:"event_id"`
	WorkerNodeID string `json:"worker_node_id"`
	Message      string `json:"message"`
}

type queueAckReply struct {
	OK       bool       `json:"ok"`
	Message  string     `json:"message"`
	Instance string     `json:"instance"`
	Item     queue.Item `json:"item"`
}

func (rt *Router) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, pingReply{OK: true, Message: "pong"})
	})
	mux.HandleFunc("/i/", rt.dispatch)
	return mux
}

func (rt *Router) dispatch(w http.ResponseWriter, r *http.Request) {
	rest := strings.TrimPrefix(r.URL.Path, "/i/")
	parts := strings.SplitN(rest, "/", 2)
	if len(parts) != 2 {
		writeJSON(w, http.StatusNotFound, pingReply{OK: false, Message: "invalid path"})
		return
	}
	instanceID := parts[0]
	action := "/" + parts[1]

	in, err := rt.reg.GetOrCreate(instanceID)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "invalid instance id"})
		return
	}

	switch action {

	case "/ping":
		writeJSON(w, http.StatusOK, pingReply{OK: true, Message: "pong"})
		return

	case "/hb":
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req hbReq
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		ts := time.Unix(req.TSUnix, 0)
		in.RecordHeartbeat(r.RemoteAddr, req.NodeID, req.Site, req.Role, ts)
		writeJSON(w, http.StatusOK, pingReply{OK: true, Message: "ok"})
		return

	case "/poll":
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		after, limit, err := parsePollQuery(r)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: err.Error()})
			return
		}
		latest, evs := in.Poll(after, limit)
		writeJSON(w, http.StatusOK, pollReply{
			OK:       true,
			Latest:   latest,
			Events:   evs,
			Instance: in.ID,
		})
		return

	// ---------------- Token ----------------

	case "/token/status":
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		now := time.Now()
		st := in.TokenStatus(now)
		writeJSON(w, http.StatusOK, tokenStatusReply{OK: true, Instance: in.ID, Token: st, NowUnix: now.Unix()})
		return

	case "/token/claim":
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req tokenActionReq
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		req.NodeID = strings.TrimSpace(req.NodeID)
		if req.NodeID == "" {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "node_id required"})
			return
		}
		now := time.Now()
		st, err := in.TokenClaim(now, req.NodeID, rt.tokenLease)
		if err == token.ErrConflict {
			writeJSON(w, http.StatusConflict, tokenActionReply{OK: false, Message: "conflict", Instance: in.ID, Token: st, NowUnix: now.Unix()})
			return
		}
		writeJSON(w, http.StatusOK, tokenActionReply{OK: true, Message: "ok", Instance: in.ID, Token: st, NowUnix: now.Unix()})
		return

	case "/token/renew":
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req tokenActionReq
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		req.NodeID = strings.TrimSpace(req.NodeID)
		if req.NodeID == "" {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "node_id required"})
			return
		}
		now := time.Now()
		st, err := in.TokenRenew(now, req.NodeID, rt.tokenLease)
		if err == token.ErrConflict {
			writeJSON(w, http.StatusConflict, tokenActionReply{OK: false, Message: "conflict", Instance: in.ID, Token: st, NowUnix: now.Unix()})
			return
		}
		if err == token.ErrNotHeld {
			writeJSON(w, http.StatusNotFound, tokenActionReply{OK: false, Message: "not_held", Instance: in.ID, Token: st, NowUnix: now.Unix()})
			return
		}
		writeJSON(w, http.StatusOK, tokenActionReply{OK: true, Message: "ok", Instance: in.ID, Token: st, NowUnix: now.Unix()})
		return

	case "/token/release":
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req tokenActionReq
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		req.NodeID = strings.TrimSpace(req.NodeID)
		if req.NodeID == "" {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "node_id required"})
			return
		}
		now := time.Now()
		st, err := in.TokenRelease(now, req.NodeID)
		if err == token.ErrConflict {
			writeJSON(w, http.StatusConflict, tokenActionReply{OK: false, Message: "conflict", Instance: in.ID, Token: st, NowUnix: now.Unix()})
			return
		}
		writeJSON(w, http.StatusOK, tokenActionReply{OK: true, Message: "ok", Instance: in.ID, Token: st, NowUnix: now.Unix()})
		return

	// ---------------- Queue ----------------

	case "/queue/enqueue":
		now := time.Now()
		st := in.TokenStatus(now)
		// ZMESH:QUEUE: enqueue is idempotent by event_id (dedupe)
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var it queue.Item
		if err := decodeJSON(r, &it, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, queueEnqReply{OK: false, Message: "bad json", Instance: in.ID})
			return
		}
		inserted, err := in.QueueEnqueue(it)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, queueEnqReply{OK: false, Message: err.Error(), Instance: in.ID})
			return
		}
		writeJSON(w, http.StatusOK, queueEnqReply{OK: true, Message: "ok", Instance: in.ID, Inserted: inserted})
		return

	case "/queue/poll":
		// ZMESH:QUEUE: lease-based polling supports worker crash recovery
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		worker := strings.TrimSpace(r.URL.Query().Get("worker"))
		limit := 64
		if v := strings.TrimSpace(r.URL.Query().Get("limit")); v != "" {
			n, e := strconv.Atoi(v)
			if e == nil && n >= 1 && n <= 512 {
				limit = n
			}
		}
		items, err := in.QueuePoll(worker, limit, time.Now())
		if err != nil {
			writeJSON(w, http.StatusBadRequest, queuePollReply{OK: false, Message: err.Error(), Instance: in.ID})
			return
		}
		writeJSON(w, http.StatusOK, queuePollReply{OK: true, Message: "ok", Instance: in.ID, Items: items})
		return

	case "/queue/ack":
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req queueAckReq
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, queueAckReply{OK: false, Message: "bad json", Instance: in.ID})
			return
		}
		req.EventID = strings.TrimSpace(req.EventID)
		req.WorkerNodeID = strings.TrimSpace(req.WorkerNodeID)
		it, err := in.QueueAck(req.EventID, req.WorkerNodeID, req.Message, time.Now())
		if err == queue.ErrConflict {
			writeJSON(w, http.StatusConflict, queueAckReply{OK: false, Message: "conflict", Instance: in.ID, Item: it})
			return
		}
		if err != nil {
			code := http.StatusBadRequest
			if err == queue.ErrNotFound {
				code = http.StatusNotFound
			}
			writeJSON(w, code, queueAckReply{OK: false, Message: err.Error(), Instance: in.ID, Item: it})
			return
		}
		writeJSON(w, http.StatusOK, queueAckReply{OK: true, Message: "ok", Instance: in.ID, Item: it})
		return

	case "/pending":
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		items := in.PendingList()

		// convert queue.Item -> pending.Item
		out := make([]pending.Item, 0, len(items))
		for _, it := range items {
			out = append(out, pending.Item{
				EventID:  it.EventID,
				NodeID:   it.NodeID,
				TSUnixMs: it.TSUnixMs,
				Kind:     it.Kind,
				Summary:  it.Summary,
			})
		}

		writeJSON(w, http.StatusOK, pending.Reply{
			OK:       true,
			Message:  "ok",
			Instance: in.ID,
			Items:    out,
		})
		return

	case "/pending/add":
		// ZMESH:PENDING:MVP: manual injection (used by sensors later)
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var it queue.Item
		if err := decodeJSON(r, &it, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		inserted, err := in.PendingAdd(it)
		if err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":       true,
			"message":  "ok",
			"instance": in.ID,
			"inserted": inserted,
		})
		return

	case "/pending/clear":
		// ZMESH:PENDING:FLAG:API
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req struct {
			NodeID string `json:"node_id"`
		}
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		nid := strings.TrimSpace(req.NodeID)
		if nid == "" {
			nid = in.NodeID()
		}
		if err := in.PendingSet(nid, false, 0); err != nil {
			writeJSON(w, http.StatusInternalServerError, pingReply{OK: false, Message: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "ok", "instance": in.ID, "node_id": nid})
		return

	case "/pending/status":
		// ZMESH:PENDING:FLAG:API
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		// node_id is optional; default to this node
		nid := strings.TrimSpace(r.URL.Query().Get("node_id"))
		if nid == "" {
			nid = in.NodeID() // 追加するgetter
		}
		st, err := in.PendingGet(nid) // 追加するメソッド
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, pingReply{OK: false, Message: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok": true, "message": "ok", "instance": in.ID,
			"node_id":             nid,
			"dirty":               st.Dirty,
			"dirty_since_unix_ms": st.DirtySinceUnixMs,
			"updated_unix_ms":     st.UpdatedUnixMs,
		})
		return

	case "/pending/set":
		// ZMESH:PENDING:FLAG:API
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		var req struct {
			NodeID      string `json:"node_id"`
			Dirty       bool   `json:"dirty"`
			SinceUnixMs int64  `json:"dirty_since_unix_ms"`
		}
		if err := decodeJSON(r, &req, 1<<20); err != nil {
			writeJSON(w, http.StatusBadRequest, pingReply{OK: false, Message: "bad json"})
			return
		}
		nid := strings.TrimSpace(req.NodeID)
		if nid == "" {
			nid = in.NodeID()
		}
		// If setting dirty and since is 0, set now.
		if req.Dirty && req.SinceUnixMs == 0 {
			req.SinceUnixMs = time.Now().UnixMilli()
		}
		if err := in.PendingSet(nid, req.Dirty, req.SinceUnixMs); err != nil {
			writeJSON(w, http.StatusInternalServerError, pingReply{OK: false, Message: err.Error()})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "message": "ok", "instance": in.ID, "node_id": nid})
		return

	case "/reconcile/run":
		// ZMESH:RECOVERY: called after (re)appointment of Logistics Chief.
		// ZMESH:SEC: later restrict to token holder / governor role.
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}

		peers := r.URL.Query()["peer"]
		if len(peers) == 0 {
			writeJSON(w, http.StatusBadRequest, reconcileReply{
				OK:       false,
				Message:  "peer query required",
				Instance: in.ID,
			})
			return
		}

		// derive this server base URL
		scheme := "http"
		if r.TLS != nil {
			scheme = "https"
		}
		selfBase := scheme + "://" + r.Host

		rc := reconcile.NewClient()

		pulled := 0
		enqNew := 0

		for _, p := range peers {
			p = strings.TrimSpace(p)
			if p == "" {
				continue
			}
			items, err := rc.PullPending(p, in.ID)
			if err != nil {
				// best effort: skip peer
				continue
			}
			pulled += len(items)

			for _, it := range items {
				inserted, err := rc.EnqueueToGovernor(selfBase, in.ID, it)
				if err == nil && inserted {
					enqNew++
				}
			}
		}

		writeJSON(w, http.StatusOK, reconcileReply{
			OK:          true,
			Message:     "ok",
			Instance:    in.ID,
			Peers:       peers,
			PulledItems: pulled,
			EnqueuedNew: enqNew,
		})
		return

	case "/bench/status":
		// ZMESH:BENCH:API
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		writeJSON(w, http.StatusOK, map[string]any{
			"ok": true, "message": "ok", "instance": in.ID,
			"links": in.BenchSnapshot(), // 追加メソッド
		})
		return

	default:
		writeJSON(w, http.StatusNotFound, pingReply{OK: false, Message: "unknown endpoint"})
		return
	}
}

func parsePollQuery(r *http.Request) (after uint64, limit int, err error) {
	q := r.URL.Query()
	if v := strings.TrimSpace(q.Get("after")); v != "" {
		after, err = strconv.ParseUint(v, 10, 64)
		if err != nil {
			return 0, 0, errors.New("invalid after")
		}
	}
	limit = 128
	if v := strings.TrimSpace(q.Get("limit")); v != "" {
		n, e := strconv.Atoi(v)
		if e != nil || n < 1 || n > 512 {
			return 0, 0, errors.New("invalid limit")
		}
		limit = n
	}
	return after, limit, nil
}

func decodeJSON(r *http.Request, dst any, max int64) error {
	defer r.Body.Close()
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, max))
	dec.DisallowUnknownFields()
	return dec.Decode(dst)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
