package verification

import (
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

// The window is what keeps "an earlier run's denial" out of this run's
// evidence now that the whole tail is read rather than a time range.
func TestScanDenyRecordIgnoresRecordsOlderThanTheWindow(t *testing.T) {
	logs := `2026-08-17T18:00:00Z WARN [ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=stale
2026-08-17T18:50:21Z WARN [ACLMon] DENY user="testuser" action=publish topic="restricted/ops/config" reason=fresh`

	cutoff := time.Date(2026, 8, 17, 18, 45, 0, 0, time.UTC)

	got := scanDenyRecord(logs, "restricted/ops/config", cutoff)
	if !contains(got, "reason=fresh") {
		t.Errorf("scanDenyRecord = %q, want the record inside the window", got)
	}

	onlyStale := `2026-08-17T18:00:00Z WARN [ACLMon] DENY user="olduser" action=publish topic="restricted/ops/config" reason=stale`
	if got := scanDenyRecord(onlyStale, "restricted/ops/config", cutoff); got != "" {
		t.Errorf("scanDenyRecord = %q, want no match for a record older than the window", got)
	}
}

// Whether Docker prefixes a timestamp is a property of the log driver, not of
// TrailMQ. An unstamped line that carries the denial still proves the claim,
// and discarding it would report the product as broken.
func TestScanDenyRecordKeepsUnstampedRecords(t *testing.T) {
	logs := `[ACLMon] DENY user="testuser" action=publish topic="restricted/ops/config" reason=acl_role_not_in_topic_scope`

	cutoff := time.Now().Add(-recordWindow)
	if got := scanDenyRecord(logs, "restricted/ops/config", cutoff); got == "" {
		t.Error("scanDenyRecord dropped a denial that Docker did not timestamp")
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
