package pending

// ZMESH:PENDING: durable change log lives on each node (future).
// MVP returns an empty list unless wired to local journal.

type Item struct {
	EventID  string `json:"event_id"`
	NodeID   string `json:"node_id"`
	TSUnixMs int64  `json:"ts_unix_ms"`
	Kind     string `json:"kind"`
	Summary  string `json:"summary"`
}

type Reply struct {
	OK       bool   `json:"ok"`
	Message  string `json:"message"`
	Instance string `json:"instance"`
	Items    []Item `json:"items"`
}
