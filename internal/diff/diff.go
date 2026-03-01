package diff

import (
	"errors"

	"github.com/EixyScience/zmesh/internal/diff/generic"
	"github.com/EixyScience/zmesh/internal/diff/zfs"
	"github.com/EixyScience/zmesh/internal/diffbase"
)

var providers = []diffbase.Provider{
	zfs.New(),
	generic.New(),
}

var ErrNoProvider = errors.New("diff: no provider succeeded")

func Detect(req diffbase.DetectRequest) (diffbase.DetectResult, error) {
	var lastErr error

	for _, p := range providers {
		if !p.Available(req.MainRoot) {
			continue
		}
		res, err := p.Detect(req)
		if err == nil && res.OK {
			return res, nil
		}
		if err != nil {
			lastErr = err
		} else if !res.OK && res.Message != "" {
			lastErr = errors.New(res.Message)
		}
	}

	if lastErr != nil {
		return diffbase.DetectResult{OK: false, Message: lastErr.Error()}, ErrNoProvider
	}
	return diffbase.DetectResult{OK: false, Message: "no provider succeeded"}, ErrNoProvider
}
