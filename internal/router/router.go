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
	"github.com/EixyScience/zmesh/internal/token"
)

type Registry struct {
	mu       sync.Mutex
	items    map[string]*instance.Instance
	ttl      time.Duration
	janitorI time.Duration
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

	// Token lease settings (MVP defaults)
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
	TSUnix int64  `json:"ts_unix"` // seconds
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

	case "/token/status":
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, pingReply{OK: false, Message: "method not allowed"})
			return
		}
		now := time.Now()
		st := in.TokenStatus(now)
		writeJSON(w, http.StatusOK, tokenStatusReply{
			OK:       true,
			Instance: in.ID,
			Token:    st,
			NowUnix:  now.Unix(),
		})
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
			writeJSON(w, http.StatusConflict, tokenActionReply{
				OK:       false,
				Message:  "conflict",
				Instance: in.ID,
				Token:    st,
				NowUnix:  now.Unix(),
			})
			return
		}
		writeJSON(w, http.StatusOK, tokenActionReply{
			OK:       true,
			Message:  "ok",
			Instance: in.ID,
			Token:    st,
			NowUnix:  now.Unix(),
		})
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
			writeJSON(w, http.StatusConflict, tokenActionReply{
				OK:       false,
				Message:  "conflict",
				Instance: in.ID,
				Token:    st,
				NowUnix:  now.Unix(),
			})
			return
		}
		if err == token.ErrNotHeld {
			writeJSON(w, http.StatusNotFound, tokenActionReply{
				OK:       false,
				Message:  "not_held",
				Instance: in.ID,
				Token:    st,
				NowUnix:  now.Unix(),
			})
			return
		}
		writeJSON(w, http.StatusOK, tokenActionReply{
			OK:       true,
			Message:  "ok",
			Instance: in.ID,
			Token:    st,
			NowUnix:  now.Unix(),
		})
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
			writeJSON(w, http.StatusConflict, tokenActionReply{
				OK:       false,
				Message:  "conflict",
				Instance: in.ID,
				Token:    st,
				NowUnix:  now.Unix(),
			})
			return
		}
		writeJSON(w, http.StatusOK, tokenActionReply{
			OK:       true,
			Message:  "ok",
			Instance: in.ID,
			Token:    st,
			NowUnix:  now.Unix(),
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
