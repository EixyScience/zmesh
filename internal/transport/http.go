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
