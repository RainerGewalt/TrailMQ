package verification

import (
	"context"
	"errors"
	"testing"
	"time"
)

// noWindow accepts every record, for the cases that are about matching rather
// than about age.
var noWindow = time.Time{}

// The line this extracts is what a user reads as the proof that a refusal was
// attributable. It has to keep the identity, role, action, topic and reason,
// and drop only the backend's own log framing.
func TestScanDenyRecordKeepsTheAttribution(t *testing.T) {
	logs := `2026-08-17T18:50:20Z INFO  [MQTT] client connected user="testuser"
2026-08-17T18:50:21Z WARN  [ACLMon] DENY user="testuser" roles=[publisher] action=publish topic="restricted/ops/config" reason=acl_role_not_in_topic_scope
2026-08-17T18:50:22Z INFO  [MQTT] client disconnected`

	got := scanDenyRecord(logs, "restricted/ops/config", noWindow)

	want := `DENY user="testuser" roles=[publisher] action=publish topic="restricted/ops/config" reason=acl_role_not_in_topic_scope`
	if got != want {
		t.Errorf("scanDenyRecord =\n  %q\nwant\n  %q", got, want)
	}
}

func TestScanDenyRecordTakesTheMostRecentMatch(t *testing.T) {
	logs := `[ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=first
[ACLMon] DENY user="testuser" action=publish topic="restricted/ops/config" reason=second`

	// An evaluation is run repeatedly against the same stack, so an earlier
	// run's denial must not be reported as this run's evidence.
	if got := scanDenyRecord(logs, "restricted/ops/config", noWindow); got == "" ||
		!contains(got, "reason=second") {
		t.Errorf("scanDenyRecord = %q, want the most recent denial", got)
	}
}

// The mark, taken from the log just before the denied publish, is what keeps
// an earlier run's denial out of this run's evidence. A denial seconds before
// the mark is as stale as one from yesterday, and so is one stamped exactly at
// it: the mark is the last line that existed before this run's publish.
func TestScanDenyRecordIgnoresRecordsAtOrBeforeTheMark(t *testing.T) {
	logs := `2026-08-17T18:50:19.5Z WARN [ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=earlier-run
2026-08-17T18:50:20.25Z WARN [ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=at-the-mark
2026-08-17T18:50:20.2500001Z WARN [ACLMon] DENY user="testuser" action=publish topic="restricted/ops/config" reason=this-run`

	mark := time.Date(2026, 8, 17, 18, 50, 20, 250000000, time.UTC)

	got := scanDenyRecord(logs, "restricted/ops/config", mark)
	if !contains(got, "reason=this-run") {
		t.Errorf("scanDenyRecord = %q, want the record logged after the mark", got)
	}

	onlyEarlier := `2026-08-17T18:50:19.5Z WARN [ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=earlier-run
2026-08-17T18:50:20.25Z WARN [ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=at-the-mark`
	if got := scanDenyRecord(onlyEarlier, "restricted/ops/config", mark); got != "" {
		t.Errorf("scanDenyRecord = %q, want no match for records at or before the mark", got)
	}
}

// Whether Docker prefixes a timestamp is a property of the log driver, not of
// TrailMQ. An unstamped line that carries the denial still proves the claim,
// and discarding it would report the product as broken.
func TestScanDenyRecordKeepsUnstampedRecords(t *testing.T) {
	logs := `[ACLMon] DENY user="testuser" action=publish topic="restricted/ops/config" reason=acl_role_not_in_topic_scope`

	mark := time.Now()
	if got := scanDenyRecord(logs, "restricted/ops/config", mark); got == "" {
		t.Error("scanDenyRecord dropped a denial that Docker did not timestamp")
	}
}

// Without a mark nothing found in the log could be told apart from an earlier
// run's record, so the check fails instead of accepting whatever matches.
func TestFindDecisionRecordFailsWithoutAMark(t *testing.T) {
	env := &Environment{BackendContainer: "not-consulted"}
	if r := env.FindDecisionRecord(context.Background(), "restricted/ops/config", time.Time{}, 0); r.Passed() {
		t.Error("FindDecisionRecord passed without a log mark")
	}
}

func TestScanDenyRecordIgnoresOtherTopicsAndOtherEvents(t *testing.T) {
	logs := `[ACLMon] DENY user="testuser" action=publish topic="other/topic" reason=x
[MQTT] publish accepted topic="restricted/ops/config"`

	// Matching either the wrong topic or a non-denial line would report a
	// refusal that never happened — the worst possible failure for a proof.
	if got := scanDenyRecord(logs, "restricted/ops/config", noWindow); got != "" {
		t.Errorf("scanDenyRecord = %q, want no match", got)
	}
}

func TestScanDenyRecordOnEmptyLogs(t *testing.T) {
	if got := scanDenyRecord("", "restricted/ops/config", noWindow); got != "" {
		t.Errorf("scanDenyRecord = %q, want empty", got)
	}
}

// "exit status 1" tells a reader nothing about a log they cannot read. The
// daemon says why, on the stream that also carries the log itself.
func TestDescribeLogFailureReportsTheDaemonsReason(t *testing.T) {
	stderr := `2026-08-17T18:50:20Z INFO  [MQTT] client connected user="testuser"
error from daemon in stream: Error grabbing logs: invalid character '\x00' looking for beginning of value
`

	got := describeLogFailure(errors.New("exit status 1"), stderr)

	want := `error from daemon in stream: Error grabbing logs: invalid character '\x00' looking for beginning of value`
	if got != want {
		t.Errorf("describeLogFailure =\n  %q\nwant\n  %q", got, want)
	}
}

// With nothing but relayed log content on stderr, the process error is all
// there is to report — and reporting a log line as the reason would be worse.
func TestDescribeLogFailureFallsBackToTheProcessError(t *testing.T) {
	stderr := "2026-08-17T18:50:20Z INFO  [MQTT] client connected\n"

	if got := describeLogFailure(errors.New("exit status 2"), stderr); got != "exit status 2" {
		t.Errorf("describeLogFailure = %q, want the process error", got)
	}
}

func contains(haystack, needle string) bool {
	return len(haystack) >= len(needle) && indexOf(haystack, needle) >= 0
}

func indexOf(haystack, needle string) int {
	for i := 0; i+len(needle) <= len(haystack); i++ {
		if haystack[i:i+len(needle)] == needle {
			return i
		}
	}
	return -1
}
