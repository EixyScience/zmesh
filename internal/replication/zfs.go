package replication

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os/exec"
	"strings"
	"time"
)

type ZFSRunner struct {
	ZFSPath  string // default "zfs"
	Timeout  time.Duration
	Verbose  bool
}

func (r *ZFSRunner) zfs() string {
	if r.ZFSPath != "" {
		return r.ZFSPath
	}
	return "zfs"
}

func (r *ZFSRunner) run(ctx context.Context, args ...string) (string, error) {
	if r.Timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, r.Timeout)
		defer cancel()
	}
	cmd := exec.CommandContext(ctx, r.zfs(), args...)
	var out bytes.Buffer
	var errb bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errb
	err := cmd.Run()
	sout := strings.TrimSpace(out.String())
	serr := strings.TrimSpace(errb.String())
	if err != nil {
		if serr != "" {
			return sout, fmt.Errorf("%w: %s", err, serr)
		}
		return sout, err
	}
	if r.Verbose && serr != "" {
		// stderr is sometimes used for debug; treat as info
	}
	return sout, nil
}

func (r *ZFSRunner) Snapshot(ctx context.Context, dataset string, tag string) (snap string, err error) {
	if dataset == "" {
		return "", errors.New("dataset is empty")
	}
	if tag == "" {
		tag = fmt.Sprintf("zmesh-%d", time.Now().Unix())
	}
	snap = dataset + "@" + tag
	_, err = r.run(ctx, "snapshot", snap)
	return snap, err
}

func (r *ZFSRunner) SendRecvSSH(ctx context.Context, snap string, to string, recvDataset string) error {
	// MVP: full send of a snapshot. Incremental will be next phase.
	// zfs send <snap> | ssh <to> zfs recv -F <recvDataset>
	if snap == "" || to == "" || recvDataset == "" {
		return errors.New("snap/to/recvDataset required")
	}

	// producer
	sendCmd := exec.CommandContext(ctx, r.zfs(), "send", snap)

	// consumer (remote)
	sshCmd := exec.CommandContext(ctx, "ssh", to, "zfs", "recv", "-F", recvDataset)

	var sendErr bytes.Buffer
	var recvErr bytes.Buffer
	sendCmd.Stderr = &sendErr
	sshCmd.Stderr = &recvErr

	pipe, err := sendCmd.StdoutPipe()
	if err != nil {
		return err
	}
	sshCmd.Stdin = pipe

	if err := sshCmd.Start(); err != nil {
		return fmt.Errorf("ssh start: %w: %s", err, strings.TrimSpace(recvErr.String()))
	}
	if err := sendCmd.Start(); err != nil {
		return fmt.Errorf("zfs send start: %w: %s", err, strings.TrimSpace(sendErr.String()))
	}

	// wait in order: send, then ssh
	if err := sendCmd.Wait(); err != nil {
		return fmt.Errorf("zfs send failed: %w: %s", err, strings.TrimSpace(sendErr.String()))
	}
	if err := sshCmd.Wait(); err != nil {
		return fmt.Errorf("ssh recv failed: %w: %s", err, strings.TrimSpace(recvErr.String()))
	}
	return nil
}