package main

import (
	"context"
	"errors"
	"fmt"
	"path/filepath"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/compose"
	"github.com/RainerGewalt/TrailMQ/internal/contract"
	"github.com/RainerGewalt/TrailMQ/internal/docker"
	"github.com/RainerGewalt/TrailMQ/internal/endpoints"
	"github.com/RainerGewalt/TrailMQ/internal/layout"
	"github.com/RainerGewalt/TrailMQ/internal/output"
	"github.com/RainerGewalt/TrailMQ/internal/platform"
	"github.com/RainerGewalt/TrailMQ/internal/provision"
)

// healthTimeout bounds how long a start waits for the stack to report healthy.
// The backend's own healthcheck has a 40s start period, so this has to be
// comfortably longer than that or a normal first start would be reported as a
// failure.
const healthTimeout = 3 * time.Minute

// session is everything a stack command needs, resolved once.
type session struct {
	contract *contract.Contract
	layout   layout.Layout
	recipe   layout.Recipe
	project  compose.Project
	points   endpoints.Endpoints
}

// openSession resolves the installation and the recipe to act on. requireSetup
// distinguishes commands that report on an existing setup from those that
// create one.
func openSession(requireSetup bool) (*session, error) {
	c, err := contract.LoadFound()
	if err != nil {
		return nil, err
	}

	l := layout.Resolve(c.Path)

	name, err := l.ActiveRecipe()
	switch {
	case errors.Is(err, layout.ErrNoActiveRecipe):
		if requireSetup {
			return nil, err
		}
		name = layout.DefaultRecipe
	case err != nil:
		return nil, err
	}

	recipe := l.Recipe(name)
	if !recipe.Exists() {
		return nil, fmt.Errorf("recipe %q is not installed in %s", name, l.Assets)
	}

	env := endpoints.EnvOverrides(l.Install)
	return &session{
		contract: c,
		layout:   l,
		recipe:   recipe,
		project:  compose.Project{Dir: recipe.Assets, Env: env},
		points:   endpoints.Load(l.Install),
	}, nil
}

// reportSetupError turns the two ways a session fails into instructions.
func reportSetupError(p *output.Printer, err error) int {
	if errors.Is(err, layout.ErrNoActiveRecipe) {
		p.Fail("TrailMQ is not set up on this machine yet.")
		p.Detail("Run 'trailmq quickstart' to prepare and start a local evaluation.")
		return exitEnvironment
	}
	p.Fail("Could not determine which TrailMQ installation to use.")
	p.Detail(err.Error())
	return exitFailure
}

// requireDocker checks the container runtime before a command that needs it,
// so the failure names the cause rather than surfacing a Compose error about a
// socket.
func requireDocker(ctx context.Context, p *output.Printer) bool {
	status := docker.Probe(ctx)
	problem, remedy, ok := status.Explain(platform.Detect())
	if ok {
		return true
	}
	p.Fail("%s", problem)
	if remedy != "" {
		p.Detail(remedy)
	}
	return false
}

func cmdStatus(out, errOut *output.Printer) int {
	s, err := openSession(true)
	if err != nil {
		return reportSetupError(errOut, err)
	}

	version, _ := s.contract.Version()
	out.Title("TrailMQ " + version)
	out.Field("Recipe", s.recipe.Name)
	out.Field("Installation", s.layout.Install)
	out.Blank()

	ctx := context.Background()
	if !requireDocker(ctx, errOut) {
		return exitEnvironment
	}

	services, err := s.project.PS(ctx)
	if err != nil {
		errOut.Fail("Could not read the container status.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	if len(services) == 0 {
		out.Warn("The stack is not running.")
		out.Detail("Run 'trailmq start' to start it.")
		return exitEnvironment
	}

	out.Title("Services")
	running := 0
	for _, svc := range services {
		line := fmt.Sprintf("%-14s %s", svc.Service, svc.Status())
		switch {
		case svc.Healthy():
			out.OK("%s", line)
			running++
		case svc.Running():
			out.Warn("%s", line)
			running++
		default:
			out.Fail("%s", line)
		}
	}

	if running == 0 {
		out.Blank()
		out.Warn("No service is running.")
		out.Detail("Run 'trailmq start' to start the stack.")
		return exitEnvironment
	}

	out.Blank()
	printEndpoints(out, s.points)

	if running < len(services) {
		out.Blank()
		out.Warn("%d of %d services are not running.", len(services)-running, len(services))
		out.Detail("Run 'trailmq logs' with the shell launcher to see why.")
		return exitEnvironment
	}
	return exitOK
}

func cmdStart(out, errOut *output.Printer) int {
	s, err := openSession(false)
	if err != nil {
		return reportSetupError(errOut, err)
	}

	ctx := context.Background()
	if !requireDocker(ctx, errOut) {
		return exitEnvironment
	}

	// A start on a machine that was never set up would otherwise fail inside
	// Compose, on a missing bind mount, with no indication of what to do.
	if !provision.CertificatesPresent(s.recipe.CertsDir()) {
		errOut.Fail("This evaluation has not been prepared yet.")
		errOut.Detail("Run 'trailmq quickstart' — it generates the local certificates and\n" +
			"credentials the stack needs, then starts it.")
		return exitEnvironment
	}

	if code := startStack(ctx, out, errOut, s); code != exitOK {
		return code
	}

	out.Blank()
	printEndpoints(out, s.points)
	return exitOK
}

func cmdStop(out, errOut *output.Printer) int {
	s, err := openSession(true)
	if err != nil {
		return reportSetupError(errOut, err)
	}

	ctx := context.Background()
	if !requireDocker(ctx, errOut) {
		return exitEnvironment
	}

	out.Step("Stopping TrailMQ…")
	if err := s.project.Down(ctx); err != nil {
		errOut.Fail("The stack did not stop cleanly.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	out.OK("Stopped.")
	// Saying this explicitly matters: "down" reads like it might have removed
	// something, and an evaluator should not have to guess whether their
	// recorded decisions survived.
	out.Dim("Your evaluation data, certificates and credentials are untouched.")
	return exitOK
}

func cmdQuickstart(out, errOut *output.Printer) int {
	s, err := openSession(false)
	if err != nil {
		return reportSetupError(errOut, err)
	}

	version, _ := s.contract.Version()
	out.Title("TrailMQ " + version + " quickstart")
	out.Dim("Secure MQTT Core with local demo certificates and generated credentials.")
	out.Blank()

	ctx := context.Background()
	if !requireDocker(ctx, errOut) {
		return exitEnvironment
	}
	out.OK("Docker is ready")

	// --- prepare ------------------------------------------------------------
	result, err := provision.Prepare(s.recipe)
	if err != nil {
		errOut.Fail("Could not prepare the evaluation.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	if result.CreatedCerts {
		out.OK("Local demo certificates generated")
		out.Detail("Self-signed, valid for one year, for local evaluation only.")
	} else {
		out.OK("Certificates present")
	}
	if result.CreatedJWTSecret {
		out.OK("JWT secret generated")
	}
	if len(result.CreatedCredentials) > 0 {
		out.OK("Evaluation credentials generated")
	} else {
		out.OK("Evaluation credentials present")
	}
	for _, user := range result.WeakPasswords {
		out.Warn("The password for %q predates the backend's password policy.", user)
		out.Detail("The backend will reject it and restart in a loop. Delete\n" +
			filepath.Join(s.recipe.SecretsDir(), user+".pwd") + " and run quickstart again.")
	}

	if err := s.layout.SetActiveRecipe(s.recipe.Name); err != nil {
		errOut.Fail("Could not record the active recipe.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	// --- pull ---------------------------------------------------------------
	out.Blank()
	out.Step("Fetching the TrailMQ images…")
	if err := s.project.Pull(ctx); err != nil {
		errOut.Fail("Could not fetch the images.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	// --- start --------------------------------------------------------------
	if code := startStack(ctx, out, errOut, s); code != exitOK {
		return code
	}

	// --- hand over ----------------------------------------------------------
	out.Blank()
	printEndpoints(out, s.points)

	if creds := provision.Credentials(s.recipe); len(creds) > 0 {
		out.Blank()
		out.Title("Evaluation login")
		for _, user := range provision.EvaluationUsers {
			if password, ok := creds[user]; ok {
				out.Field(user, password)
			}
		}
		out.Dim("Local use only.")
	}

	out.Blank()
	out.Title("Next")
	out.Println("  trailmq open        Open TrailMQ in your browser")
	out.Println("  ./trailmq verify    Run the decision proof")
	return exitOK
}

// startStack brings the stack up and waits for it to report healthy.
func startStack(ctx context.Context, out, errOut *output.Printer, s *session) int {
	// Another TrailMQ installation running under the same Compose project name.
	// Starting would silently recreate its containers against this
	// installation's data, taking down an evaluation that belongs to someone
	// else's window. Checked first, because it is the failure that does not
	// announce itself.
	if hijacked, err := compose.HijackedProject(ctx, s.recipe.Assets); err == nil && len(hijacked) > 0 {
		errOut.Fail("Another TrailMQ installation is already running these containers:")
		for _, name := range hijacked {
			errOut.Detail(name)
		}
		errOut.Detail("Starting here would take that stack over, because Docker Compose names\n" +
			"the project after the recipe folder and both installations use the same one.\n" +
			"Stop the other installation first, or remove its containers with\n" +
			"'docker rm -f <name>'. Bind-mounted data stays on disk either way.")
		return exitFailure
	}

	// Containers left behind by an earlier setup hold the names this stack
	// needs. Compose reports that as a name conflict, which says nothing about
	// where the other container came from.
	if foreign, err := compose.ForeignContainers(ctx, compose.ProjectName(s.recipe.Assets)); err == nil && len(foreign) > 0 {
		errOut.Fail("Containers from another setup are using TrailMQ's names:")
		for _, name := range foreign {
			errOut.Detail(name)
		}
		errOut.Detail("Remove them with 'docker rm -f <name>' and try again.\n" +
			"Bind-mounted data stays on disk — only the container hulls are removed.")
		return exitFailure
	}

	out.Blank()
	out.Step("Starting TrailMQ…")
	if err := s.project.Up(ctx); err != nil {
		errOut.Fail("The stack did not start.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	out.Step("Waiting for the stack to become healthy…")
	healthy, err := waitForHealth(ctx, s.project, healthTimeout)
	if err != nil {
		errOut.Fail("Could not determine whether the stack is healthy.")
		errOut.Detail(err.Error())
		return exitFailure
	}
	if !healthy {
		errOut.Fail("The stack started but did not become healthy in time.")
		errOut.Detail("Run 'trailmq status' to see which service is stuck.")
		return exitEnvironment
	}

	out.OK("TrailMQ is running.")
	return exitOK
}

// waitForHealth polls until every service reports healthy, or the deadline
// passes. Polling Compose is used rather than probing the HTTP endpoint
// because the recipe already declares what healthy means for each service, and
// duplicating that here would let the two definitions drift.
func waitForHealth(ctx context.Context, project compose.Project, timeout time.Duration) (bool, error) {
	deadline := time.Now().Add(timeout)
	for {
		services, err := project.PS(ctx)
		if err != nil {
			return false, err
		}

		allHealthy := len(services) > 0
		for _, svc := range services {
			if !svc.Healthy() {
				allHealthy = false
				break
			}
		}
		if allHealthy {
			return true, nil
		}
		if time.Now().After(deadline) {
			return false, nil
		}

		select {
		case <-ctx.Done():
			return false, ctx.Err()
		case <-time.After(2 * time.Second):
		}
	}
}

func printEndpoints(p *output.Printer, e endpoints.Endpoints) {
	p.Title("Open TrailMQ")
	p.Field("Web UI", p.Link(e.WebUI()))
	p.Field("REST API", p.Link(e.RestAPI()))
	p.Field("MQTT TLS", p.Link(e.MQTTOverTLS()))
	p.Field("MQTT WebSocket", p.Link(e.MQTTOverWebSocket()))
}
