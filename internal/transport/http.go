package transport

import (
"bytes"
"context"
"encoding/json"
"io"
"net"
"net/http"
"time"
)

type PingReply struct {
OK      bool    + "json:\"ok\"" + 
Message string  + "json:\"message\"" + 
}

type Heartbeat struct {
NodeID string  + "json:\"node_id\"" + 
Site   string  + "json:\"site\"" + 
Role   string  + "json:\"role\"" + 
TSUnix int64   + "json:\"ts_unix\"" + 
}

type HTTP struct {
Listen string
Peers  []string
}

func (h *HTTP) Serve(ctx context.Context, onHB func(from string, hb Heartbeat)) error {
mux := http.NewServeMux()

mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
_ = json.NewEncoder(w).Encode(PingReply{OK: true, Message: "pong"})
})

mux.HandleFunc("/hb", func(w http.ResponseWriter, r *http.Request) {
defer r.Body.Close()
body, _ := io.ReadAll(io.LimitReader(r.Body, 1<<20))
var hb Heartbeat
if err := json.Unmarshal(body, &hb); err != nil {
w.WriteHeader(http.StatusBadRequest)
_ = json.NewEncoder(w).Encode(PingReply{OK: false, Message: "bad json"})
return
}
if onHB != nil { onHB(r.RemoteAddr, hb) }
_ = json.NewEncoder(w).Encode(PingReply{OK: true, Message: "ok"})
})

srv := &http.Server{
Addr:              h.Listen,
Handler:           mux,
ReadHeaderTimeout: 3 * time.Second,
}

ln, err := net.Listen("tcp", h.Listen)
if err != nil { return err }

go func() { <-ctx.Done(); _ = srv.Shutdown(context.Background()) }()
return srv.Serve(ln)
}

func (h *HTTP) Ping(baseURL string, timeout time.Duration) (bool, string, error) {
c := &http.Client{Timeout: timeout}
resp, err := c.Get(baseURL + "/ping")
if err != nil { return false, "connect failed", err }
defer resp.Body.Close()
if resp.StatusCode != 200 { return false, resp.Status, nil }
return true, "pong", nil
}

func (h *HTTP) SendHeartbeat(hb Heartbeat, timeout time.Duration) {
b, _ := json.Marshal(hb)
c := &http.Client{Timeout: timeout}
for _, base := range h.Peers {
req, _ := http.NewRequest("POST", base+"/hb", bytes.NewReader(b))
req.Header.Set("Content-Type", "application/json")
_, _ = c.Do(req)
}
}
