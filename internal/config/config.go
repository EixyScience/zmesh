package config

import (
	"bufio"
	"errors"
	"os"
	"strings"
)

type Config struct {
	Node struct{ ID, Site string }
	LAN  struct {
		UDPListen string
		UDPPeers  []string
	}
	WAN struct {
		Enabled bool
		Listen  string
		Peers   []string
	}
	Role struct {
		Prime    bool
		Governor bool
	}
}

func Load(path string) (*Config, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	cfg := &Config{}
	sec := ""

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		line = strings.TrimPrefix(line, "\ufeff")
		if line == "" || strings.HasPrefix(line, ";") || strings.HasPrefix(line, "#") {
			continue
		}
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			sec = strings.ToLower(strings.TrimSpace(line[1 : len(line)-1]))
			continue
		}
		k, v, ok := strings.Cut(line, "=")
		if !ok {
			return nil, errors.New("invalid line: " + line)
		}
		key := strings.ToLower(strings.TrimSpace(k))
		val := strings.TrimSpace(v)

		switch sec {
		case "node":
			if key == "id" {
				cfg.Node.ID = val
			}
			if key == "site" {
				cfg.Node.Site = val
			}
		case "lan":
			if key == "udp_listen" {
				cfg.LAN.UDPListen = val
			}
			if key == "udp_peers" {
				cfg.LAN.UDPPeers = splitCSV(val)
			}
		case "wan":
			if key == "enabled" {
				cfg.WAN.Enabled = parseBool(val)
			}
			if key == "listen" {
				cfg.WAN.Listen = val
			}
			if key == "peers" {
				cfg.WAN.Peers = splitCSV(val)
			}
		case "role":
			if key == "prime" {
				cfg.Role.Prime = parseBool(val)
			}
			if key == "governor" {
				cfg.Role.Governor = parseBool(val)
			}
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return cfg, nil
}

func splitCSV(s string) []string {
	raw := strings.Split(s, ",")
	out := make([]string, 0, len(raw))
	for _, r := range raw {
		t := strings.TrimSpace(r)
		if t != "" {
			out = append(out, t)
		}
	}
	return out
}
func parseBool(s string) bool {
	switch strings.ToLower(strings.TrimSpace(s)) {
	case "1", "true", "yes", "y", "on":
		return true
	default:
		return false
	}
}
