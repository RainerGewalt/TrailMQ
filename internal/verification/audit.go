package verification

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
)

// AuditIntegrity validates the hash-linked system and action audit chain.
//
// The scope of this claim is narrow on purpose, and the product says so in its
// own UI: the chain covers sign-ins, administrative changes, identity and role
// changes, and policy changes. MQTT decision records live in a separate store
// that this validation does not walk. A caller reporting this result must not
// widen it into "every MQTT decision is tamper-checked", because that is not
// what was verified.
func (e *Environment) AuditIntegrity(ctx context.Context, token string) Result {
	const key, title = "audit_chain", "System/action audit chain intact"

	if token == "" {
		return fail(key, title, "no API token — the chain could not be validated")
	}

	body, resp, err := e.get(ctx, token, "/audit/validatechain")
	if err != nil {
		return fail(key, title, "the API did not answer: "+firstLine(err.Error()))
	}
	if resp.StatusCode != http.StatusOK {
		return fail(key, title, "validating the chain returned "+resp.Status)
	}

	var answer struct {
		Valid          bool `json:"valid"`
		CheckedEntries int  `json:"checkedEntries"`
	}
	if err := json.Unmarshal(body, &answer); err != nil {
		return fail(key, title, "the response could not be read: "+firstLine(err.Error()))
	}
	if !answer.Valid {
		return fail(key, title, fmt.Sprintf("the chain did not validate (%d entries checked)",
			answer.CheckedEntries))
	}

	return pass(key, title).
		withFact("audit_chain_entries", strconv.Itoa(answer.CheckedEntries))
}
