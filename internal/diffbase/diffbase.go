package diffbase

import "errors"

func Detect(req DetectRequest) (DetectResult, error) {
	providers := []Provider{
		zfsCLIProvider{},
		GenericIndexProvider{},
	}

	var lastErr error
	var lastMsg string

	for _, p := range providers {
		if !p.Available(req.MainRoot) {
			continue
		}
		res, err := p.Detect(req)
		if err == nil && res.OK {
			if res.Provider == "" {
				res.Provider = p.Name()
			}
			return res, nil
		}
		if err != nil {
			lastErr = err
		}
		if !res.OK && res.Message != "" {
			lastMsg = res.Message
		}
	}

	msg := "no provider succeeded"
	if lastMsg != "" {
		msg += ": " + lastMsg
	} else if lastErr != nil {
		msg += ": " + lastErr.Error()
	}

	if lastErr == nil {
		lastErr = errors.New(msg)
	}
	return DetectResult{OK: false, Message: msg}, lastErr
}
