package diffbase

import (
	"os"
	"path/filepath"
	"strings"
)

func sigPath(stateDir, instanceID, nodeID string) string {
	return filepath.Join(stateDir, "preflight", instanceID, nodeID+".sig")
}

func loadSig(stateDir, instanceID, nodeID string) (string, error) {
	fp := sigPath(stateDir, instanceID, nodeID)
	b, err := os.ReadFile(fp)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(string(b)), nil
}

func saveSig(stateDir, instanceID, nodeID, sig string) error {
	fp := sigPath(stateDir, instanceID, nodeID)
	if err := os.MkdirAll(filepath.Dir(fp), 0o755); err != nil {
		return err
	}
	tmp := fp + ".tmp"
	if err := os.WriteFile(tmp, []byte(sig+"\n"), 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, fp)
}
