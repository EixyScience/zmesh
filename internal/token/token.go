package token

import (
	"errors"
	"time"
)

var (
	ErrConflict = errors.New("token: conflict")
	ErrNotHeld  = errors.New("token: not held")
)

type State struct {
	HolderNodeID string    `json:"holder_node_id"`
	IssuedAt     time.Time `json:"issued_at"`
	ExpiresAt    time.Time `json:"expires_at"`
	Epoch        uint64    `json:"epoch"` // increments each time token is (re)issued after being free/expired
}

func (s State) Active(now time.Time) bool {
	return s.HolderNodeID != "" && now.Before(s.ExpiresAt)
}

func (s State) Expired(now time.Time) bool {
	if s.HolderNodeID == "" {
		return true
	}
	return !now.Before(s.ExpiresAt)
}
