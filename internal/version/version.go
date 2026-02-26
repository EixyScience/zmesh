package version

var (
	Version = "0.0.0"
	Commit  = "dev"
)

func String() string { return "zmesh " + Version + " (" + Commit + ")" }
