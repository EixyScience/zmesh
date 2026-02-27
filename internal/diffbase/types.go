package diffbase

type DetectRequest struct {
	InstanceID string
	NodeID     string

	MainRoot string
	StateDir string

	Excludes []string
}

type DetectResult struct {
	OK      bool
	Message string

	Changed bool

	MainSig     string
	PrevMainSig string

	Provider string

	PendingMaybeSet bool
}

type Provider interface {
	Name() string
	Available(root string) bool
	Detect(req DetectRequest) (DetectResult, error)
}
