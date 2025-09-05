package ipfs

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

type Client struct {
	gateway string
	hc      *http.Client
}

func NewClient(gateway string) *Client {
	return &Client{
		gateway: strings.TrimRight(gateway, "/"),
		hc:      &http.Client{Timeout: 15 * time.Second},
	}
}

func (c *Client) Resolve(uri string) (string, error) {
	if !strings.HasPrefix(uri, "ipfs://") {
		return "", fmt.Errorf("unsupported uri scheme: %s", uri)
	}
	rest := strings.TrimPrefix(uri, "ipfs://")
	return c.gateway + "/" + rest, nil
}

func (c *Client) Fetch(ctx context.Context, uri string, maxBytes int64) ([]byte, error) {
	url, err := c.Resolve(uri)
	if err != nil {
		return nil, err
	}
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	resp, err := c.hc.Do(req)
	if err != nil {
		return nil, fmt.Errorf("ipfs http get: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return nil, fmt.Errorf("ipfs http status: %d", resp.StatusCode)
	}
	var r io.Reader = resp.Body
	if maxBytes > 0 {
		r = io.LimitReader(resp.Body, maxBytes)
	}
	b, err := io.ReadAll(r)
	if err != nil {
		return nil, fmt.Errorf("ipfs read: %w", err)
	}
	return b, nil
}
