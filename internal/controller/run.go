package controller

import (
	"time"
)

func (c *Controller) Run() {

	for {

		scalefs, _ := c.Discover()

		for _, s := range scalefs {

			if c.IsDirty(s) {

				c.handleDirty(s)

			}
		}

		time.Sleep(5 * time.Second)
	}
}



func (c *Controller) handleDirty(path string) {

	if c.ZFS {

		// TODO dataset detect
		// replicate via zfs

	} else {

		// rsync fallback

	}
}











