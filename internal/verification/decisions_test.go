package verification

import "testing"

// The line this extracts is what a user reads as the proof that a refusal was
// attributable. It has to keep the identity, role, action, topic and reason,
// and drop only the backend's own log framing.
func TestScanDenyRecordKeepsTheAttribution(t *testing.T) {
	logs := `2026-08-17T18:50:20Z INFO  [MQTT] client connected user="testuser"
2026-08-17T18:50:21Z WARN  [ACLMon] DENY user="testuser" roles=[publisher] action=publish topic="restricted/ops/config" reason=acl_role_not_in_topic_scope
2026-08-17T18:50:22Z INFO  [MQTT] client disconnected`

	got := scanDenyRecord(logs, "restricted/ops/config")

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
	if got := scanDenyRecord(logs, "restricted/ops/config"); got == "" ||
		!contains(got, "reason=second") {
		t.Errorf("scanDenyRecord = %q, want the most recent denial", got)
	}
}

func TestScanDenyRecordIgnoresOtherTopicsAndOtherEvents(t *testing.T) {
	logs := `[ACLMon] DENY user="testuser" action=publish topic="other/topic" reason=x
[MQTT] publish accepted topic="restricted/ops/config"`

	// Matching either the wrong topic or a non-denial line would report a
	// refusal that never happened — the worst possible failure for a proof.
	if got := scanDenyRecord(logs, "restricted/ops/config"); got != "" {
		t.Errorf("scanDenyRecord = %q, want no match", got)
	}
}

func TestScanDenyRecordOnEmptyLogs(t *testing.T) {
	if got := scanDenyRecord("", "restricted/ops/config"); got != "" {
		t.Errorf("scanDenyRecord = %q, want empty", got)
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
