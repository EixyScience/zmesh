package membership

import (
"context"
"encoding/json"
"net"
"time"
)

type Heartbeat struct {
NodeID string  + "json:\"node_id\"" + 
Site   string  + "json:\"site\"" + 
TSUnix int64   + "json:\"ts_unix\"" + 
}

type UDP struct {
Listen string
Peers  []string
}

func (u *UDP) Serve(ctx context.Context, onRecv func(from string, hb Heartbeat)) error {
addr, err := net.ResolveUDPAddr("udp", u.Listen)
if err != nil { return err }
conn, err := net.ListenUDP("udp", addr)
if err != nil { return err }
defer conn.Close()

buf := make([]byte, 64*1024)
for {
_ = conn.SetReadDeadline(time.Now().Add(1 * time.Second))
n, raddr, err := conn.ReadFromUDP(buf)
if err != nil {
select { case <-ctx.Done(): return nil; default: continue }
}
var hb Heartbeat
if json.Unmarshal(buf[:n], &hb) == nil && onRecv != nil {
onRecv(raddr.String(), hb)
}
}
}

func (u *UDP) Send(hb Heartbeat) {
b, _ := json.Marshal(hb)
for _, p := range u.Peers {
raddr, err := net.ResolveUDPAddr("udp", p)
if err != nil { continue }
conn, err := net.DialUDP("udp", nil, raddr)
if err != nil { continue }
_, _ = conn.Write(b)
_ = conn.Close()
}
}
