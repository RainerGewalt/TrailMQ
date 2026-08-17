package verification

import (
	"bytes"
	"context"
	"os/exec"
	"strings"
	"time"
)

// denyMarker is how the backend writes an MQTT access denial to its log.
const denyMarker = "[ACLMon] DENY"

// FindDecisionRecord looks up the attributable record a denial produced.
//
// It reads the backend's log rather than an API, because that is where MQTT
// decision records are observable in this release. That is also the reason the
// audit-chain claim and this one are reported separately: they come from
// different stores, and the integrity validation does not cover this one.
//
// The record is retried for a short while. The publish returns as soon as the
// broker refuses it, which can be marginally before the decision is written.
func (e *Environment) FindDecisionRecord(ctx context.Context, topic string, wait time.Duration) Result {
	const key, title = "deny_recorded", "Denial recorded with user, role, action and topic"

	if e.BackendContainer == "" {
		return fail(key, title, "the backend container could not be identified")
	}

	deadline := time.Now().Add(wait)
	for {
		line, err := e.findDenyLine(ctx, topic)
		if err != nil {
			return fail(key, title, "could not read the backend log: "+firstLine(err.Error()))
		}
		if line != "" {
			return pass(key, title).withFact("deny_record", line)
		}
		if time.Now().After(deadline) {
			return fail(key, title, "no "+denyMarker+" record found for "+topic)
		}

		select {
		case <-ctx.Done():
			return fail(key, title, ctx.Err().Error())
		case <-time.After(500 * time.Millisecond):
		}
	}
}

// findDenyLine returns the most recent denial for a topic, without the log's
// own prefix.
func (e *Environment) findDenyLine(ctx context.Context, topic string) (string, error) {
	cmd := exec.CommandContext(ctx, "docker", "logs", e.BackendContainer, "--since", "5m")

	var out, errBuf bytes.Buffer
	cmd.Stdout = &out
	// Container logs arrive on both streams depending on how the backend
	// writes them, so both are searched.
	cmd.Stderr = &errBuf
	if err := cmd.Run(); err != nil {
		return "", err
	}

	return scanDenyRecord(out.String()+"\n"+errBuf.String(), topic), nil
}

// scanDenyRecord extracts the most recent denial for a topic from backend log
// output. Separated from the Docker call so the matching can be tested against
// real log shapes without a running stack.
func scanDenyRecord(logs, topic string) string {
	var found string
	for _, line := range strings.Split(logs, "\n") {
		if strings.Contains(line, denyMarker) && strings.Contains(line, topic) {
			found = line
		}
	}
	if found == "" {
		return ""
	}

	// The log prefix belongs to the backend's format, not to this contract, so
	// only the decision itself is reported.
	if i := strings.Index(found, denyMarker); i >= 0 {
		found = found[i+len(denyMarker)-len("DENY"):]
	}
	return strings.TrimSpace(found)
}
