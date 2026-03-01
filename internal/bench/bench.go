package bench

import (
	"sync"
	"time"
)

// ZMESH:BENCH:MVP
// Benchmark Chief keeps rolling measurements useful for ActiveSet (clear quorum)
// and relay tree construction.
// For now: in-memory only; sources are HTTP timings / send throughput observations.

type Link struct {
	Peer    string `json:"peer"`
	RttMs   int64  `json:"rtt_ms"`
	BwBps   int64  `json:"bw_bps"`
	LossPPM int64  `json:"loss_ppm"`
	Updated int64  `json:"updated_unix_ms"`
}

type Store struct {
	mu    sync.Mutex
	links map[string]Link // peer -> link
}

func NewStore() *Store {
	return &Store{links: make(map[string]Link, 256)}
}

func (s *Store) Update(peer string, rttMs, bwBps, lossPPM int64) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.links[peer] = Link{
		Peer:    peer,
		RttMs:   rttMs,
		BwBps:   bwBps,
		LossPPM: lossPPM,
		Updated: time.Now().UnixMilli(),
	}
}

func (s *Store) Snapshot() []Link {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]Link, 0, len(s.links))
	for _, v := range s.links {
		out = append(out, v)
	}
	return out
}
