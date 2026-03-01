package reconcile

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/EixyScience/zmesh/internal/queue"
)

// ZMESH:RECOVERY: reconcile pulls pending from peers then enqueues to governor queue.
// ZMESH:EXTEND: peer discovery via membership + site/governor graph.

type Client struct {
	HTTPTimeout time.Duration
}

func NewClient() *Client {
	return &Client{HTTPTimeout: 3 * time.Second}
}

type pendingReply struct {
	OK       bool   `json:"ok"`
	Message  string `json:"message"`
	Instance string `json:"instance"`
	Items    []struct {
		EventID  string `json:"event_id"`
		NodeID   string `json:"node_id"`
		TSUnixMs int64  `json:"ts_unix_ms"`
		Kind     string `json:"kind"`
		Summary  string `json:"summary"`
	} `json:"items"`
}

type enqueueReply struct {
	OK       bool   `json:"ok"`
	Message  string `json:"message"`
	Instance string `json:"instance"`
	Inserted bool   `json:"inserted"`
}

func (c *Client) PullPending(peerBaseURL, instanceID string) ([]queue.Item, error) {
	url := fmt.Sprintf("%s/i/%s/pending", peerBaseURL, instanceID)

	hc := &http.Client{Timeout: c.HTTPTimeout}
	resp, err := hc.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var pr pendingReply
	if err := json.NewDecoder(resp.Body).Decode(&pr); err != nil {
		return nil, err
	}
	if !pr.OK {
		return nil, fmt.Errorf("pending not ok: %s", pr.Message)
	}

	out := make([]queue.Item, 0, len(pr.Items))
	for _, x := range pr.Items {
		out = append(out, queue.Item{
			EventID:  x.EventID,
			NodeID:   x.NodeID,
			TSUnixMs: x.TSUnixMs,
			Kind:     x.Kind,
			Summary:  x.Summary,
		})
	}
	return out, nil
}

func (c *Client) EnqueueToGovernor(govBaseURL, instanceID string, it queue.Item) (bool, error) {
	url := fmt.Sprintf("%s/i/%s/queue/enqueue", govBaseURL, instanceID)

	b, _ := json.Marshal(it)
	hc := &http.Client{Timeout: c.HTTPTimeout}
	req, err := http.NewRequest("POST", url, bytes.NewReader(b))
	if err != nil {
		return false, err
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := hc.Do(req)
	if err != nil {
		return false, err
	}
	defer resp.Body.Close()

	var er enqueueReply
	if err := json.NewDecoder(resp.Body).Decode(&er); err != nil {
		return false, err
	}
	if !er.OK {
		return false, fmt.Errorf("enqueue not ok: %s", er.Message)
	}
	return er.Inserted, nil
}
