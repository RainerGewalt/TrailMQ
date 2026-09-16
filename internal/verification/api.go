package verification

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"
)

var (
	clientOnce sync.Once
	client     *http.Client
)

// httpClient talks to the reverse proxy on the host.
//
// The shell proof reaches the REST API with `docker exec … wget`, because the
// backend's own port is internal. Going through the published proxy instead
// exercises the same path an evaluator's browser and scripts use, and removes
// a Docker dependency from a check that is about the API.
func httpClient() *http.Client {
	clientOnce.Do(func() {
		client = &http.Client{Timeout: 20 * time.Second}
	})
	return client
}

// APIAuthentication proves the REST API issues a token for a valid identity,
// and returns the token so later probes can use it.
func (e *Environment) APIAuthentication(ctx context.Context, id Identity) (Result, string) {
	const key, title = "api_auth", "REST API authentication issues a token"

	body, err := json.Marshal(map[string]string{
		"username": id.Username,
		"password": id.Password,
	})
	if err != nil {
		return fail(key, title, err.Error()), ""
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		e.Endpoints.RestAPI()+"/auth", bytes.NewReader(body))
	if err != nil {
		return fail(key, title, err.Error()), ""
	}
	req.Header.Set("Content-Type", "application/json")

	resp, err := httpClient().Do(req)
	if err != nil {
		return fail(key, title, "the API did not answer: "+firstLine(err.Error())), ""
	}
	defer resp.Body.Close()

	payload, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode != http.StatusOK {
		return fail(key, title, fmt.Sprintf("sign-in as %s returned %s", id.Username, resp.Status)), ""
	}

	var answer struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(payload, &answer); err != nil || answer.Token == "" {
		return fail(key, title, "the response carried no token"), ""
	}
	return pass(key, title), answer.Token
}

// get performs an authenticated GET against the REST API.
func (e *Environment) get(ctx context.Context, token, path string) ([]byte, *http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, e.Endpoints.RestAPI()+path, nil)
	if err != nil {
		return nil, nil, err
	}
	req.Header.Set("Authorization", "Bearer "+token)

	resp, err := httpClient().Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	return body, resp, err
}

// BackendVersion reports the build the runtime identifies itself as, so a
// report can name what was actually exercised rather than what was expected.
func (e *Environment) BackendVersion(ctx context.Context) string {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, e.Endpoints.RestAPI()+"/version", nil)
	if err != nil {
		return ""
	}
	resp, err := httpClient().Do(req)
	if err != nil {
		return ""
	}
	defer resp.Body.Close()

	var answer struct {
		Version string `json:"version"`
	}
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	if json.Unmarshal(body, &answer) != nil {
		return ""
	}
	return answer.Version
}
