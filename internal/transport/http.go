package transport

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"time"

	"github.com/EixyScience/zmesh/internal/router"
)

type HTTP struct {
	Listen string
	Peers  []string

	RegistryTTL time.Duration
}

func (h *HTTP) Serve(ctx context.Context) error {
	reg := router.NewRegistry(h.RegistryTTL)
	rt := router.New(reg)

	mux := rt.Handler()

	srv := &http.Server{
		Addr:              h.Listen,
		Handler:           mux,
		ReadHeaderTimeout: 3 * time.Second,
	}

	ln, err := net.Listen("tcp", h.Listen)
	if err != nil {
		return err
	}

	go reg.RunJanitor(ctx)
	go func() {
		<-ctx.Done()
		_ = srv.Shutdown(context.Background())
	}()

	return srv.Serve(ln)
}

// ZMESH:TOKEN: HTTP client for token operations

type TokenState struct {
	HolderNodeID string    `json:"holder_node_id"`
	IssuedAt     time.Time `json:"issued_at"`
	ExpiresAt    time.Time `json:"expires_at"`
	Epoch        uint64    `json:"epoch"`
}

type tokenReply struct {
	OK       bool       `json:"ok"`
	Message  string     `json:"message"`
	Instance string     `json:"instance"`
	Token    TokenState `json:"token"`
	NowUnix  int64      `json:"now_unix"`
}

func (h *HTTP) Ping(baseURL string, timeout time.Duration) (bool, string, error) {
	c := &http.Client{Timeout: timeout}
	resp, err := c.Get(baseURL + "/ping")
	if err != nil {
		return false, "connect failed", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return false, fmt.Sprintf("status=%d", resp.StatusCode), nil
	}
	return true, "pong", nil
}

type Heartbeat struct {
	NodeID string `json:"node_id"`
	Site   string `json:"site"`
	Role   string `json:"role"`
	TSUnix int64  `json:"ts_unix"`
}

func (h *HTTP) SendHeartbeat(instanceID string, hb Heartbeat, timeout time.Duration) {
	b, _ := json.Marshal(hb)
	c := &http.Client{Timeout: timeout}
	for _, base := range h.Peers {
		// instance-scoped endpoint
		url := fmt.Sprintf("%s/i/%s/hb", base, instanceID)
		req, _ := http.NewRequest("POST", url, bytes.NewReader(b))
		req.Header.Set("Content-Type", "application/json")
		_, _ = c.Do(req)
	}
}

// ZMESH:TOKEN: Claim token for scalefs instance
func (h *HTTP) TokenClaim(baseURL, instanceID, nodeID string, timeout time.Duration) (TokenState, error) {
	return h.tokenPost(baseURL, instanceID, "claim", nodeID, timeout)
}

// ZMESH:TOKEN: Renew token lease
func (h *HTTP) TokenRenew(baseURL, instanceID, nodeID string, timeout time.Duration) (TokenState, error) {
	return h.tokenPost(baseURL, instanceID, "renew", nodeID, timeout)
}

// ZMESH:TOKEN: Release token lease
func (h *HTTP) TokenRelease(baseURL, instanceID, nodeID string, timeout time.Duration) (TokenState, error) {
	return h.tokenPost(baseURL, instanceID, "release", nodeID, timeout)
}

func (h *HTTP) tokenPost(baseURL, instanceID, action, nodeID string, timeout time.Duration) (TokenState, error) {

	url := fmt.Sprintf("%s/i/%s/token/%s", baseURL, instanceID, action)

	reqBody := map[string]string{"node_id": nodeID}
	b, _ := json.Marshal(reqBody)

	c := &http.Client{Timeout: timeout}

	req, err := http.NewRequest("POST", url, bytes.NewReader(b))
	if err != nil {
		return TokenState{}, err
	}

	req.Header.Set("Content-Type", "application/json")

	resp, err := c.Do(req)
	if err != nil {
		return TokenState{}, err
	}
	defer resp.Body.Close()

	var reply tokenReply

	err = json.NewDecoder(resp.Body).Decode(&reply)
	if err != nil {
		return TokenState{}, err
	}

	if !reply.OK {
		return reply.Token, fmt.Errorf("token %s failed: %s", action, reply.Message)
	}

	return reply.Token, nil
}
