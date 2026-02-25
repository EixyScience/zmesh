package agent

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/EixyScience/zmesh/internal/config"
	"github.com/EixyScience/zmesh/internal/membership"
	"github.com/EixyScience/zmesh/internal/transport"
)

type Agent struct {
	cfg *config.Config
}

func New(cfg *config.Config) *Agent { return &Agent{cfg: cfg} }

func (a *Agent) Run() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	var recvCount uint64

	// LAN UDP
	udp := &membership.UDP{
		Listen: a.cfg.LAN.UDPListen,
		Peers:  a.cfg.LAN.UDPPeers,
	}

	go func() {
		_ = udp.Serve(ctx, func(from string, hb membership.Heartbeat) {
			atomic.AddUint64(&recvCount, 1)
			fmt.Printf("[lan] recv from=%s node=%s site=%s ts=%d\n", from, hb.NodeID, hb.Site, hb.TSUnix)
		})
	}()

	// WAN HTTP (optional)
	var httpx *transport.HTTP
	if a.cfg.WAN.Enabled {
		httpx = &transport.HTTP{
			Scheme: a.cfg.WAN.Scheme,
			Listen: a.cfg.WAN.Listen,
			Peers:  a.cfg.WAN.Peers,
		}
		go func() {
			_ = httpx.Serve(ctx, func(from string, hb transport.Heartbeat) {
				fmt.Printf("[wan] recv from=%s node=%s site=%s role=%s ts=%d\n", from, hb.NodeID, hb.Site, hb.Role, hb.TSUnix)
			})
		}()
	}

	role := "node"
	if a.cfg.Role.Prime {
		role = "prime"
	} else if a.cfg.Role.Governor {
		role = "governor"
	}

	// send loop
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	// signal handling
	sigc := make(chan os.Signal, 2)
	signal.Notify(sigc, syscall.SIGINT, syscall.SIGTERM)

	fmt.Printf("zmesh agent start node=%s site=%s role=%s lan=%s wan=%v\n",
		a.cfg.Node.ID, a.cfg.Node.Site, role, a.cfg.LAN.UDPListen, a.cfg.WAN.Enabled)

	for {
		select {
		case <-sigc:
			fmt.Println("zmesh agent stopping...")
			cancel()
			return nil
		case t := <-ticker.C:
			udp.Send(membership.Heartbeat{
				NodeID: a.cfg.Node.ID,
				Site:   a.cfg.Node.Site,
				TSUnix: t.Unix(),
			})
			if httpx != nil {
				httpx.SendHeartbeat(transport.Heartbeat{
					NodeID: a.cfg.Node.ID,
					Site:   a.cfg.Node.Site,
					Role:   role,
					TSUnix: t.Unix(),
				}, 2*time.Second)
			}
		}
	}
}

func PingHTTP(baseURL string, timeout time.Duration) (bool, string, error) {
	h := &transport.HTTP{}
	return h.Ping(baseURL, timeout)
}
