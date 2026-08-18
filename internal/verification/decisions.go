package verification

import (
	"bytes"
	"context"
	"errors"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

// denyMarker is how the backend writes an MQTT access denial to its log.
const denyMarker = "[ACLMon] DENY"

// recordWindow is how far back a denial is accepted from. An evaluation is run
// repeatedly against the same stack, so a denial from an earlier run must not
// be reported as this run's evidence.
const recordWindow = 5 * time.Minute

// recordTails are the tail sizes readBackendLog asks Docker for, in order.
//
// The first is the working size: on an evaluation stack it spans well over an
// hour of log, far more than recordWindow. The smaller ones exist because
// Docker cannot read past a corrupted region in a container's log file, and a
// machine can carry one from an earlier unclean daemon shutdown — nothing to
// do with TrailMQ, but enough to make this proof unobtainable. The record
// being looked for was written seconds ago and sits at the very end, so when a
// read fails, asking for less of the log answers the question more often than
// giving up on it does.
var recordTails = []int{400, 100, 25}

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

	// Fixed before the first attempt rather than per attempt, so retrying does
	// not slowly widen the window a record is accepted from.
	cutoff := time.Now().Add(-recordWindow)

	deadline := time.Now().Add(wait)
	for {
		line, err := e.findDenyLine(ctx, topic, cutoff)
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
func (e *Environment) findDenyLine(ctx context.Context, topic string, cutoff time.Time) (string, error) {
	logs, err := e.readBackendLog(ctx)
	if err != nil {
		return "", err
	}
	return scanDenyRecord(logs, topic, cutoff), nil
}

// readBackendLog returns the end of the backend's container log, with the
// timestamps Docker itself recorded.
//
// It reads backwards from the end with --tail rather than asking for a time
// range with --since. Docker serves --since by scanning the log file from the
// beginning, so a single corrupted region makes every --since read fail for
// the rest of that container's life, however recent the wanted entry is. The
// time window --since would have given is applied by the caller instead, over
// the timestamps requested here.
func (e *Environment) readBackendLog(ctx context.Context) (string, error) {
	var lastErr error

	for _, tail := range recordTails {
		cmd := exec.CommandContext(ctx, "docker", "logs", e.BackendContainer,
			"--tail", strconv.Itoa(tail), "--timestamps")

		var out, errBuf bytes.Buffer
		cmd.Stdout = &out
		// Container logs arrive on both streams depending on how the backend
		// writes them, so both are kept.
		cmd.Stderr = &errBuf
		if err := cmd.Run(); err != nil {
			lastErr = errors.New(describeLogFailure(err, errBuf.String()))
			continue
		}
		return out.String() + "\n" + errBuf.String(), nil
	}
	return "", lastErr
}

// describeLogFailure says why `docker logs` failed, in the daemon's own words.
//
// The process itself only reports "exit status 1"; the cause is on stderr,
// which also carries log content. The daemon's message is the last line that
// is not a timestamped log line — with --timestamps, everything Docker relays
// from the container is stamped and its own errors are not.
func describeLogFailure(err error, stderr string) string {
	lines := strings.Split(stderr, "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if line == "" {
			continue
		}
		if _, _, stamped := splitTimestamp(line); stamped {
			continue
		}
		return line
	}
	return err.Error()
}

// splitTimestamp separates the timestamp Docker puts in front of a line under
// --timestamps from the line the backend itself wrote.
func splitTimestamp(line string) (time.Time, string, bool) {
	stamp, rest, ok := strings.Cut(line, " ")
	if !ok {
		return time.Time{}, line, false
	}
	at, err := time.Parse(time.RFC3339Nano, stamp)
	if err != nil {
		return time.Time{}, line, false
	}
	return at, rest, true
}

// scanDenyRecord extracts the most recent denial for a topic from backend log
// output, ignoring records written before cutoff. Separated from the Docker
// call so the matching can be tested against real log shapes without a running
// stack.
//
// A line Docker did not stamp is still considered. Dropping it would mean that
// a Docker version or log driver which omits the prefix silently produces "no
// denial was recorded" — reporting the product as broken because of how its
// logs were relayed.
func scanDenyRecord(logs, topic string, cutoff time.Time) string {
	var found string
	for _, line := range strings.Split(logs, "\n") {
		at, entry, stamped := splitTimestamp(line)
		if stamped && at.Before(cutoff) {
			continue
		}
		if strings.Contains(entry, denyMarker) && strings.Contains(entry, topic) {
			found = entry
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
