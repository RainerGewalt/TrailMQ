package main

import (
	"context"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/output"
	"github.com/RainerGewalt/TrailMQ/internal/provision"
	"github.com/RainerGewalt/TrailMQ/internal/verification"
)

// cmdVerify runs the decision proof.
//
// It is deliberately thin. Every check below is a probe in
// internal/verification, so the demo scenarios can make the same observations
// without a second implementation — and so this file stays a statement of
// which claims are proven, in what order, rather than of how.
func cmdVerify(out, errOut *output.Printer, args []string) int {
	resultFile := ""
	for i := 0; i < len(args); i++ {
		switch args[i] {
		case "--result-file":
			if i+1 >= len(args) {
				errOut.Fail("--result-file needs a path")
				return exitUsage
			}
			resultFile = args[i+1]
			i++
		default:
			errOut.Fail("Unknown option for 'verify': %s", args[i])
			return exitUsage
		}
	}

	s, err := openSession(true)
	if err != nil {
		return reportSetupError(errOut, err)
	}

	ctx := context.Background()
	if !requireDocker(ctx, errOut) {
		return exitEnvironment
	}

	env, err := verification.Open(ctx, s.recipe, s.points, s.project)
	if err != nil {
		errOut.Fail("The evaluation is not ready to be verified.")
		errOut.Detail(err.Error())
		errOut.Detail("Run 'trailmq quickstart' first.")
		return exitEnvironment
	}

	admin, err := env.Identity("testadmin", "trailmq-verify-dashboard")
	if err != nil {
		errOut.Fail("%s", err.Error())
		return exitEnvironment
	}
	publisher, err := env.Identity("testuser", "trailmq-verify-sensor")
	if err != nil {
		errOut.Fail("%s", err.Error())
		return exitEnvironment
	}

	out.Title("TrailMQ decision proof")
	out.Dim("Not just \"is it running\" — does it decide, enforce and record?")
	out.Blank()

	report := newReport(out, resultFile)

	// The runtime has to answer before anything else means anything.
	if !report.record(env.RuntimeReady(ctx, 30*time.Second)) {
		return report.finish(errOut)
	}

	report.record(env.AuthenticatedMQTT(ctx, admin))

	// An allowed publish, observed arriving at a second authenticated client.
	// The payload is unique to this run so a replayed message cannot satisfy it.
	const allowedTopic = "public/demo/temperature"
	report.record(env.PublishAndObserve(ctx, verification.DeliverySpec{
		Publisher:  publisher,
		Subscriber: admin,
		Filter:     "public/#",
		Topic:      allowedTopic,
		Payload: verification.Payload(`{"value":21.4,"unit":"degC","verify":"%d"}`,
			time.Now().UnixNano()),
	}))

	// The same identity, a namespace its role does not reach.
	const deniedTopic = "restricted/ops/config"
	report.record(env.ExpectPublishDenied(ctx, verification.DenialSpec{
		Publisher: publisher,
		Topic:     deniedTopic,
		Payload:   []byte("should-not-arrive"),
	}))

	report.record(env.FindDecisionRecord(ctx, deniedTopic, 10*time.Second))

	apiResult, token := env.APIAuthentication(ctx, admin)
	report.record(apiResult)
	report.record(env.AuditIntegrity(ctx, token))

	if version := env.BackendVersion(ctx); version != "" {
		out.Blank()
		out.Dim("Backend    %s", version)
		out.Dim("Recipe     %s", s.recipe.Name)
		out.Dim("Checked    %s", time.Now().UTC().Format(time.RFC3339))
	}

	if report.passed == report.total {
		out.Blank()
		out.Title("That is the difference")
		out.Println("  TrailMQ applied the configured access rules, refused the unauthorized")
		out.Println("  action, and kept its decision record.")
		out.Blank()
		out.Printf("  See it: %s → Activity → filter Outcome: Denied\n", out.Link(s.points.WebUI()))
		out.Println("  Sign in as testadmin — 'trailmq credentials' prints the password.")
	}

	return report.finish(errOut)
}

// report accumulates results, prints them, and writes the machine-readable
// result file.
//
// The result-file keys are a published contract: the guided run reads them
// instead of parsing human output, so a reworded label can never silently
// break it. These seven carry "pass" or "fail" and match the shell proof's
// keys exactly:
//
//	ready, tls_listener, allow, deny, deny_recorded, api_auth, audit_chain
//
// Everything else is informational and must not be asserted on. Alongside the
// shell proof's audit_chain_entries, deny_record, checks_passed and
// checks_total, this implementation adds two facts the probes can now observe:
//
//	delivered_topic  the topic the payload actually arrived on
//	denied_at        whether the refusal happened at connect or at publish
//
// Consumers read by key, so additional keys are safe; the shell proof's
// readers ignore them.
type report struct {
	out    *output.Printer
	path   string
	lines  []string
	passed int
	total  int
}

func newReport(out *output.Printer, path string) *report {
	r := &report{out: out, path: path}
	if path != "" {
		// Truncated up front: a stale file from an earlier run must never be
		// mistaken for this one's result.
		_ = os.WriteFile(path, nil, 0o644)
	}
	return r
}

func (r *report) record(result verification.Result) bool {
	r.total++
	label := result.Title
	if result.Passed() {
		r.passed++
		r.out.OK("%s", label)
		r.emit(result.Key, "pass")
	} else {
		r.out.Fail("%s", label)
		if result.Detail != "" {
			r.out.Detail(result.Detail)
		}
		r.emit(result.Key, "fail")
	}

	keys := make([]string, 0, len(result.Facts))
	for k := range result.Facts {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, k := range keys {
		r.emit(k, result.Facts[k])
		if k == "deny_record" {
			r.out.Detail(result.Facts[k])
		}
	}

	return result.Passed()
}

func (r *report) emit(key, value string) {
	if r.path == "" {
		return
	}
	r.lines = append(r.lines, key+"\t"+value)
}

func (r *report) finish(errOut *output.Printer) int {
	r.emit("checks_passed", strconv.Itoa(r.passed))
	r.emit("checks_total", strconv.Itoa(r.total))

	if r.path != "" && len(r.lines) > 0 {
		if err := os.WriteFile(r.path, []byte(strings.Join(r.lines, "\n")+"\n"), 0o644); err != nil {
			errOut.Warn("Could not write the result file: %s", err)
		}
	}

	r.out.Blank()
	r.out.Println(fmt.Sprintf("%d/%d checks passed", r.passed, r.total))

	if r.passed == r.total && r.total > 0 {
		return exitOK
	}
	r.out.Blank()
	r.out.Dim("Something failed? Run 'trailmq doctor' and 'trailmq status'.")
	return exitFailure
}

// cmdCredentials prints the generated evaluation logins.
//
// It exists because the first-run flow produces credentials and an evaluator
// needs them again five minutes later. Sending someone to a file path under a
// recipe directory is a poor answer anywhere, and a worse one on Windows.
func cmdCredentials(out, errOut *output.Printer) int {
	s, err := openSession(true)
	if err != nil {
		return reportSetupError(errOut, err)
	}

	creds := provision.Credentials(s.recipe)
	if len(creds) == 0 {
		errOut.Fail("No evaluation credentials have been generated yet.")
		errOut.Detail("Run 'trailmq quickstart' to create them.")
		return exitEnvironment
	}

	out.Title("Evaluation login")
	for _, user := range provision.EvaluationUsers {
		if password, ok := creds[user]; ok {
			out.Field(user, password)
		}
	}
	out.Blank()
	out.Dim("Local evaluation only. Sign in at %s", s.points.WebUI())
	return exitOK
}
