package agent

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"github.com/EixyScience/zmesh/internal/config"
	"github.com/EixyScience/zmesh/internal/id"
	"github.com/EixyScience/zmesh/internal/instance"
	"github.com/EixyScience/zmesh/internal/membership"
	"github.com/EixyScience/zmesh/internal/transport"
)

type Agent struct {
	Cfg        *config.Config
	ConfigPath string // -c で渡された zmesh.conf のパス
}

// tools
func absFrom(baseDir, p string) string {
	if p == "" {
		return ""
	}
	if filepath.IsAbs(p) {
		return filepath.Clean(p)
	}
	return filepath.Clean(filepath.Join(baseDir, p))
}

// main functions
func New(cfg *config.Config, configPath string) *Agent {
	return &Agent{Cfg: cfg, ConfigPath: configPath}
}

func (a *Agent) Run() error {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// configファイルのディレクトリを取得（-c の zmesh.conf の場所）
	baseDir := filepath.Dir(a.ConfigPath)

	// まずは “デフォルト” を絶対パスにして注入（paths を config 側に生やしたらここを差し替える）
	defaults := instance.Paths{
		StateDir:     absFrom(baseDir, "./zmesh.state"),
		WatchRoot:    absFrom(baseDir, "./main"),
		WatchExclude: []string{"./zmesh.state/**"},
	}

	//defaults := instance.Paths{
	//	StateDir:     absFrom(baseDir, a.Cfg.Paths.StateDir),
	//	WatchRoot:    absFrom(baseDir, a.Cfg.Paths.WatchRoot),
	//	WatchExclude: a.Cfg.Paths.WatchExclude,
	//}
	//reg := router.NewRegistry(0, defaults)
	//reg := router.NewRegistryWithDefaults(0, defaults)
	//rt := router.New(reg)

	// LAN UDP
	udp := &membership.UDP{
		Listen: a.Cfg.LAN.UDPListen,
		Peers:  a.Cfg.LAN.UDPPeers,
	}
	go func() {
		_ = udp.Serve(ctx, func(from string, hb membership.Heartbeat) {
			fmt.Printf("[lan] recv from=%s node=%s site=%s ts=%d\n", from, hb.NodeID, hb.Site, hb.TSUnix)
		})
	}()

	// Role string
	role := "node"
	if a.Cfg.Role.Prime {
		role = "prime"
	} else if a.Cfg.Role.Governor {
		role = "governor"
	}

	// ScaleFS instance ID (UUIDv7)
	instanceID := a.Cfg.ScaleFS.ID
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
	if a.Cfg.WAN.Enabled {
		httpx = &transport.HTTP{
			Listen:           a.Cfg.WAN.Listen,
			Peers:            a.Cfg.WAN.Peers,
			RegistryDefaults: defaults,
			RegistryTTL:      10 * time.Minute, // lazy instances expire if unused
		}
		// ZMESH:TOKEN: automatic claim/renew loop
		// ZMESH:EXTEND: replace with distributed consensus when orchestration layer is implemented
		if httpx != nil {

			go func() {

				base := ""
				if len(a.Cfg.WAN.Peers) > 0 {
					base = a.Cfg.WAN.Peers[0]
				}

				if base == "" {
					fmt.Println("[token] no WAN peer configured; skipping auto-claim")
					return
				}

				nodeID := a.Cfg.Node.ID

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
		a.Cfg.Node.ID, a.Cfg.Node.Site, role, instanceID, a.Cfg.LAN.UDPListen, a.Cfg.WAN.Enabled)

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
				NodeID: a.Cfg.Node.ID,
				Site:   a.Cfg.Node.Site,
				TSUnix: t.Unix(),
			})
			if httpx != nil {
				httpx.SendHeartbeat(instanceID, transport.Heartbeat{
					NodeID: a.Cfg.Node.ID,
					Site:   a.Cfg.Node.Site,
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
