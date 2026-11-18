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

// recordTails are the tail sizes readBackendLog asks Docker for, in order.
//
// The first is the working size: on an evaluation stack it spans well over an
// hour of log, far more than one run needs. The smaller ones exist because
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
// Only a record logged after mark counts. mark is what MarkBackendLog returned
// before the denied publish, so a denial from an earlier run against the same
// stack, however recent, is never reported as this run's evidence. A zero mark
// means the log could not be marked, and nothing found could then be told
// apart from an earlier run's record.
//
// The record is retried for a short while. The publish returns as soon as the
// broker refuses it, which can be marginally before the decision is written.
func (e *Environment) FindDecisionRecord(ctx context.Context, topic string, mark time.Time, wait time.Duration) Result {
	const key, title = "deny_recorded", "Denial recorded with user, role, action and topic"

	if e.BackendContainer == "" {
		return fail(key, title, "the backend container could not be identified")
	}
	if mark.IsZero() {
		return fail(key, title, "the backend log could not be marked before the denied publish")
	}

	deadline := time.Now().Add(wait)
	for {
		line, err := e.findDenyLine(ctx, topic, mark)
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

// MarkBackendLog returns the timestamp Docker gave the newest line of the
// backend's log. Taken before a denied publish, it separates that publish's
// record from every earlier one. Both this mark and the records it is compared
// with are stamped by the Docker daemon, so the comparison involves no local
// clock and no waiting. The zero time is returned with the error when the log
// holds no stamped line or cannot be read.
func (e *Environment) MarkBackendLog(ctx context.Context) (time.Time, error) {
	if e.BackendContainer == "" {
		return time.Time{}, errors.New("the backend container could not be identified")
	}
	cmd := exec.CommandContext(ctx, "docker", "logs", e.BackendContainer, "--tail", "1", "--timestamps")
	var out, errBuf bytes.Buffer
	cmd.Stdout = &out
	cmd.Stderr = &errBuf
	if err := cmd.Run(); err != nil {
		return time.Time{}, errors.New(describeLogFailure(err, errBuf.String()))
	}
	var mark time.Time
	for _, line := range strings.Split(out.String()+"\n"+errBuf.String(), "\n") {
		if at, _, stamped := splitTimestamp(strings.TrimSpace(line)); stamped && at.After(mark) {
			mark = at
		}
	}
	if mark.IsZero() {
		return time.Time{}, errors.New("the backend log holds no timestamped line")
	}
	return mark, nil
}

// findDenyLine returns the most recent denial for a topic logged after mark,
// without the log's own prefix.
func (e *Environment) findDenyLine(ctx context.Context, topic string, mark time.Time) (string, error) {
	logs, err := e.readBackendLog(ctx)
	if err != nil {
		return "", err
	}
	return scanDenyRecord(logs, topic, mark), nil
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
// output, ignoring records stamped at or before mark. Separated from the Docker
// call so the matching can be tested against real log shapes without a running
// stack.
//
// A line Docker did not stamp is still considered. Dropping it would mean that
// a Docker version or log driver which omits the prefix silently produces "no
// denial was recorded" — reporting the product as broken because of how its
// logs were relayed.
func scanDenyRecord(logs, topic string, mark time.Time) string {
	var found string
	for _, line := range strings.Split(logs, "\n") {
		at, entry, stamped := splitTimestamp(line)
		if stamped && !at.After(mark) {
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
