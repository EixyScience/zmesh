package pendingstore

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

// ZMESH:PENDING: durable *flag* (dirty or not). Minimal state.
// NOTE: location must be outside watched area OR excluded by watch config.

var ErrBadInput = errors.New("pendingstore: bad input")

type State struct {
	Dirty            bool  `json:"dirty"`
	DirtySinceUnixMs int64 `json:"dirty_since_unix_ms"`
	UpdatedUnixMs    int64 `json:"updated_unix_ms"`
}

type Store struct {
	BaseDir string // e.g. "./zmesh.state/pending"
}

func New(baseDir string) (*Store, error) {
	if baseDir == "" {
		return nil, ErrBadInput
	}
	if err := os.MkdirAll(baseDir, 0o755); err != nil {
		return nil, err
	}
	return &Store{BaseDir: baseDir}, nil
}

// Path scheme: <BaseDir>/<instance>/<node>.json
func (s *Store) filePath(instanceID, nodeID string) (string, error) {
	if instanceID == "" || nodeID == "" {
		return "", ErrBadInput
	}
	dir := filepath.Join(s.BaseDir, instanceID)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	return filepath.Join(dir, nodeID+".json"), nil
}

func (s *Store) Get(instanceID, nodeID string) (State, error) {
	fp, err := s.filePath(instanceID, nodeID)
	if err != nil {
		return State{}, err
	}
	b, err := os.ReadFile(fp)
	if err != nil {
		if os.IsNotExist(err) {
			return State{Dirty: false}, nil
		}
		return State{}, err
	}
	var st State
	if err := json.Unmarshal(b, &st); err != nil {
		// Corrupt file -> treat as not dirty (safe default)
		return State{Dirty: false}, nil
	}
	return st, nil
}

func (s *Store) Set(instanceID, nodeID string, dirty bool, sinceUnixMs int64) error {
	fp, err := s.filePath(instanceID, nodeID)
	if err != nil {
		return err
	}

	nowMs := time.Now().UnixMilli()

	st := State{
		Dirty:            dirty,
		DirtySinceUnixMs: sinceUnixMs,
		UpdatedUnixMs:    nowMs,
	}
	// If clearing, since becomes 0
	if !dirty {
		st.DirtySinceUnixMs = 0
	}

	b, _ := json.Marshal(st)

	tmp := fp + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, fp)
}
