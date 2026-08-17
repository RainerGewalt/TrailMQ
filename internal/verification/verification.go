// Package verification holds TrailMQ's product proofs as reusable pieces.
//
// These are the checks that distinguish "the containers are up" from "the
// product does what it claims": an authorized publish reaches a subscriber, an
// unauthorized one is refused, the refusal exists as an attributable record,
// and the audit chain still validates.
//
// They are modelled as parameterised probes rather than as a script, because
// two very different features need the same substrate. `trailmq verify`
// answers "does this release honour its technical promise?" and is a fixed
// PASS/FAIL run. A demo scenario answers "what does TrailMQ do, in a situation
// I recognise?" and is a narrative. Both publish as an identity, observe
// delivery, expect a denial and look up the decision it produced. Implementing
// that twice would let the demo drift away from the proof, which is the one
// thing a demo must never do.
//
// Nothing here contains product narrative or user-facing story. Probes report
// what happened; callers decide what it means.
package verification

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/RainerGewalt/TrailMQ/internal/compose"
	"github.com/RainerGewalt/TrailMQ/internal/endpoints"
	"github.com/RainerGewalt/TrailMQ/internal/layout"
	"github.com/RainerGewalt/TrailMQ/internal/provision"
)

// Identity is an MQTT or REST identity taking part in a check.
//
// ClientID matters: it is what makes an action attributable in the record the
// broker keeps, so a probe that omitted it would weaken the very claim it is
// meant to prove.
type Identity struct {
	Username string
	Password string
	ClientID string
}

// Environment is a running evaluation the probes act against.
type Environment struct {
	Recipe    layout.Recipe
	Endpoints endpoints.Endpoints
	Project   compose.Project

	// BackendContainer is resolved from Compose rather than assumed, so a
	// stack started under a different project name is still readable.
	BackendContainer string

	caCert      []byte
	credentials map[string]string
}

// Open resolves everything the probes need from a prepared installation.
func Open(ctx context.Context, recipe layout.Recipe, points endpoints.Endpoints, project compose.Project) (*Environment, error) {
	ca, err := os.ReadFile(filepath.Join(recipe.CertsDir(), "ca_cert.pem"))
	if err != nil {
		return nil, fmt.Errorf("the demo CA certificate is missing: %w", err)
	}

	creds := provision.Credentials(recipe)
	if len(creds) == 0 {
		return nil, fmt.Errorf("no evaluation credentials found in %s", recipe.SecretsDir())
	}

	env := &Environment{
		Recipe:      recipe,
		Endpoints:   points,
		Project:     project,
		caCert:      ca,
		credentials: creds,
	}

	services, err := project.PS(ctx)
	if err != nil {
		return nil, fmt.Errorf("could not inspect the running stack: %w", err)
	}
	for _, svc := range services {
		if svc.Service == "backend" {
			env.BackendContainer = svc.Name
		}
	}
	if env.BackendContainer == "" {
		return nil, fmt.Errorf("the backend container is not running")
	}

	return env, nil
}

// Identity returns a named evaluation identity with its generated password.
func (e *Environment) Identity(username, clientID string) (Identity, error) {
	password, ok := e.credentials[username]
	if !ok {
		return Identity{}, fmt.Errorf("no password found for %q — run 'trailmq quickstart' first", username)
	}
	return Identity{Username: username, Password: password, ClientID: clientID}, nil
}

// Status is the outcome of a probe.
type Status int

const (
	Pass Status = iota
	Fail
)

// Result is what a probe observed.
//
// Key is a stable machine identifier and part of the published result-file
// contract; Title and Detail are for people and may be reworded freely.
type Result struct {
	Key    string
	Title  string
	Status Status
	Detail string
	// Facts carries informational values that are reported but never asserted
	// on — an audit chain's entry count moves with every sign-in.
	Facts map[string]string
}

func (r Result) Passed() bool { return r.Status == Pass }

func pass(key, title string) Result {
	return Result{Key: key, Title: title, Status: Pass}
}

func fail(key, title, detail string) Result {
	return Result{Key: key, Title: title, Status: Fail, Detail: detail}
}

func (r Result) withFact(name, value string) Result {
	if r.Facts == nil {
		r.Facts = map[string]string{}
	}
	r.Facts[name] = value
	return r
}

// firstLine keeps a multi-line runtime error from spilling across a report.
func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}
