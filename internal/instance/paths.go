package instance

// Paths are per-node defaults used by APIs like /preflight/run.
// IMPORTANT: store absolute paths here to avoid cwd-dependency.
type Paths struct {
	StateDir     string   // absolute
	WatchRoot    string   // absolute
	WatchExclude []string // patterns (implementation-defined)
}
