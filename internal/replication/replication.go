package replication

import (
	"context"
	"errors"

	"github.com/EixyScience/zmesh/internal/manifest"
)

type Engine struct {
	ZFS *ZFSRunner
}

type SendRequest struct {
	BodyDir      string
	ToSSH        string // user@host
	RecvDataset  string // e.g. pool/scalefs (base) or exact dataset
	Tag          string // snapshot tag override (optional)
}

func (e *Engine) Manifest(bodyDir string) (*manifest.Manifest, error) {
	return manifest.LoadFromBodyDir(bodyDir)
}

func (e *Engine) Snapshot(ctx context.Context, bodyDir string, tag string) (string, error) {
	m, err := manifest.LoadFromBodyDir(bodyDir)
	if err != nil {
		return "", err
	}
	if !m.ZFS.Enabled || m.ZFS.Dataset == "" {
		return "", errors.New("zfs not enabled or dataset missing in scalefs.ini")
	}
	if e.ZFS == nil {
		return "", errors.New("ZFS runner is nil")
	}
	return e.ZFS.Snapshot(ctx, m.ZFS.Dataset, tag)
}

func (e *Engine) Send(ctx context.Context, req SendRequest) (string, error) {
	if e.ZFS == nil {
		return "", errors.New("ZFS runner is nil")
	}
	m, err := manifest.LoadFromBodyDir(req.BodyDir)
	if err != nil {
		return "", err
	}
	if !m.ZFS.Enabled || m.ZFS.Dataset == "" {
		return "", errors.New("zfs not enabled or dataset missing in scalefs.ini")
	}

	snap, err := e.ZFS.Snapshot(ctx, m.ZFS.Dataset, req.Tag)
	if err != nil {
		return "", err
	}

	// recv dataset:
	// MVP: allow caller to pass exact dataset. If they pass "pool/scalefs" treat as base and append name-shortid.
	recv := req.RecvDataset
	if recv == "" {
		return "", errors.New("RecvDataset is required")
	}
	// If looks like base path, append name-shortid
	// (very simple heuristic: no '-' means base, but you can refine later)
	if !containsLeaf(recv) {
		recv = recv + "/" + m.Scalefs.Name + "-" + m.Scalefs.ShortID
	}

	if err := e.ZFS.SendRecvSSH(ctx, snap, req.ToSSH, recv); err != nil {
		return snap, err
	}
	return snap, nil
}

func containsLeaf(ds string) bool {
	// crude: if it already ends with name-shortid style (has '-'), treat as leaf
	// refine later with config.
	for i := len(ds) - 1; i >= 0; i-- {
		if ds[i] == '/' {
			break
		}
		if ds[i] == '-' {
			return true
		}
	}
	return false
}