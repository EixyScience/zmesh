package controller

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

type Controller struct {
	NodeID string

	ScalefsRoots []string

	ZFS bool
}

func New(nodeID string, roots []string) *Controller {

	return &Controller{
		NodeID: nodeID,
		ScalefsRoots: roots,
		ZFS: detectZFS(),
	}
}

func detectZFS() bool {

	_, err := os.Stat("/sbin/zfs")
	if err == nil {
		return true
	}

	_, err = os.Stat("/usr/sbin/zfs")
	return err == nil
}

func (c *Controller) Discover() ([]string, error) {

	var out []string

	for _, root := range c.ScalefsRoots {

		entries, err := os.ReadDir(root)
		if err != nil {
			continue
		}

		for _, e := range entries {

			if !e.IsDir() {
				continue
			}

			main := filepath.Join(root, e.Name(), "main")

			if _, err := os.Stat(main); err == nil {
				out = append(out, filepath.Join(root, e.Name()))
			}
		}
	}

	return out, nil
}



func (c *Controller) IsDirty(path string) bool {

	state := filepath.Join(path, "scalefs.state")

	s, err := os.Stat(state)

	if err != nil {
		return false
	}

	return time.Since(s.ModTime()) < time.Minute
}



package controller

import (
	"fmt"
	"os/exec"
)

func (c *Controller) ReplicateZFS(dataset, target string) error {

	cmd := exec.Command("zfs",
		"send",
		dataset)

	recv := exec.Command("ssh",
		target,
		"zfs receive "+dataset)

	pipe, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}

	recv.Stdin = pipe

	err = cmd.Start()
	if err != nil {
		return err
	}

	err = recv.Run()
	if err != nil {
		return err
	}

	return cmd.Wait()
}



func (c *Controller) ReplicateGeneric(src, dst string) error {

	cmd := exec.Command(
		"rsync",
		"-a",
		src+"/",
		dst+"/",
	)

	return cmd.Run()
}








