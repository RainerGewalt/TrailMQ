package verification

import (
	"context"
	"net/http"
	"time"
)

// RuntimeReady reports whether the backend is answering.
//
// This is the precondition every other probe rests on, and it is checked
// through the product's own readiness endpoint rather than through container
// state: a container can be running while the backend inside it is still
// opening its database.
func (e *Environment) RuntimeReady(ctx context.Context, wait time.Duration) Result {
	const key, title = "ready", "Runtime ready"

	url := e.Endpoints.Ready()
	deadline := time.Now().Add(wait)
	lastErr := "no response"

	for {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return fail(key, title, err.Error())
		}

		resp, err := httpClient().Do(req)
		if err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return pass(key, title)
			}
			lastErr = resp.Status
		} else {
			lastErr = firstLine(err.Error())
		}

		if time.Now().After(deadline) {
			return fail(key, title,
				"the backend never reported ready at "+url+" ("+lastErr+")")
		}

		select {
		case <-ctx.Done():
			return fail(key, title, ctx.Err().Error())
		case <-time.After(time.Second):
		}
	}
}
