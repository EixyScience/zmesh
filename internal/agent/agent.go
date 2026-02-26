package agent

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/EixyScience/zmesh/internal/config"
	"github.com/EixyScience/zmesh/internal/id"
	"github.com/EixyScience/zmesh/internal/membership"
	"github.com/EixyScience/zmesh/internal/transport"
)

type Agent struct{ cfg *config.Config }

func New(cfg *config.Config) *Agent { return &Agent{cfg: cfg} }

func (a *Agent) Run() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// LAN UDP
	udp := &membership.UDP{
		Listen: a.cfg.LAN.UDPListen,
		Peers:  a.cfg.LAN.UDPPeers,
	}
	go func() {
		_ = udp.Serve(ctx, func(from string, hb membership.Heartbeat) {
			fmt.Printf("[lan] recv from=%s node=%s site=%s ts=%d\n", from, hb.NodeID, hb.Site, hb.TSUnix)
		})
	}()

	// Role string
	role := "node"
	if a.cfg.Role.Prime {
		role = "prime"
	} else if a.cfg.Role.Governor {
		role = "governor"
	}

	// ScaleFS instance ID (UUIDv7)
	instanceID := a.cfg.ScaleFS.ID
	if instanceID == "" {
		u, err := id.NewUUID7()
		if err != nil {
			return err
		}
		instanceID = u
		fmt.Printf("[warn] scalefs.id missing; generated uuid7=%s (set it in config)\n", instanceID)
	} else if err := id.ValidateUUID(instanceID); err != nil {
		return fmt.Errorf("invalid scalefs.id: %w", err)
	}

	// WAN HTTP (optional)
	var httpx *transport.HTTP
	if a.cfg.WAN.Enabled {
		httpx = &transport.HTTP{
			Listen:      a.cfg.WAN.Listen,
			Peers:       a.cfg.WAN.Peers,
			RegistryTTL: 10 * time.Minute, // lazy instances expire if unused
		}
		// ZMESH:TOKEN: automatic claim/renew loop
		// ZMESH:EXTEND: replace with distributed consensus when orchestration layer is implemented
		if httpx != nil {

			go func() {

				base := ""
				if len(a.cfg.WAN.Peers) > 0 {
					base = a.cfg.WAN.Peers[0]
				}

				if base == "" {
					fmt.Println("[token] no WAN peer configured; skipping auto-claim")
					return
				}

				nodeID := a.cfg.Node.ID

				for {

					select {
					case <-ctx.Done():
						// ZMESH:TOKEN: release on shutdown (best effort)
						_, _ = httpx.TokenRelease(base, instanceID, nodeID, 2*time.Second)
						return

					default:

						// ZMESH:TOKEN: claim or renew
						st, err := httpx.TokenClaim(base, instanceID, nodeID, 2*time.Second)

						if err != nil {

							// ZMESH:TOKEN: conflict or unreachable
							// ZMESH:EXTEND: add exponential backoff and alternate governor selection

							time.Sleep(5 * time.Second)
							continue
						}

						fmt.Printf("[token] holder=%s epoch=%d expires=%s\n",
							st.HolderNodeID,
							st.Epoch,
							st.ExpiresAt.Format(time.RFC3339))

						// ZMESH:TOKEN: renew interval (lease=30s → renew every 10s)
						time.Sleep(10 * time.Second)
					}
				}
			}()
		}

		go func() {
			_ = httpx.Serve(ctx)
		}()
	}

	// signal handling
	sigc := make(chan os.Signal, 2)
	signal.Notify(sigc, syscall.SIGINT, syscall.SIGTERM)

	fmt.Printf("zmesh agent start node=%s site=%s role=%s scalefs=%s lan=%s wan=%v\n",
		a.cfg.Node.ID, a.cfg.Node.Site, role, instanceID, a.cfg.LAN.UDPListen, a.cfg.WAN.Enabled)

	tick := time.NewTicker(1 * time.Second)
	defer tick.Stop()

	for {
		select {
		case <-sigc:
			fmt.Println("zmesh agent stopping...")
			cancel()
			return nil
		case t := <-tick.C:
			udp.Send(membership.Heartbeat{
				NodeID: a.cfg.Node.ID,
				Site:   a.cfg.Node.Site,
				TSUnix: t.Unix(),
			})
			if httpx != nil {
				httpx.SendHeartbeat(instanceID, transport.Heartbeat{
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
