package bench

import "time"

// ZMESH:ACTIVESET:MVP
// ActiveSet is "currently alive" nodes within a time window.
// Later we can incorporate EWMA RTT/BW/loss to filter "main nodes".

type ActiveSet struct {
	Window time.Duration // e.g. 90s
	Now    time.Time
}

func (a ActiveSet) Contains(lastSeen time.Time) bool {
	if lastSeen.IsZero() {
		return false
	}
	if a.Window <= 0 {
		a.Window = 90 * time.Second
	}
	// alive if seen within Window
	return a.Now.Sub(lastSeen) <= a.Window
}

func Quorum(n int) int {
	if n <= 0 {
		return 0
	}
	return (n / 2) + 1
}
