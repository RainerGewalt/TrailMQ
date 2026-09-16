package compose

import (
	"strings"
	"testing"
)

// Compose has emitted two different shapes for `ps --format json` depending on
// its version, and an evaluator's version is not something the launcher gets
// to choose. Reading only one of them would make status silently report an
// empty stack.
func TestParsePSAcceptsBothComposeOutputShapes(t *testing.T) {
	const array = `[
	  {"Name":"trailmq-backend","Service":"backend","State":"running","Health":"healthy"},
	  {"Name":"trailmq-frontend","Service":"frontend","State":"running","Health":""}
	]`

	const ndjson = `{"Name":"trailmq-backend","Service":"backend","State":"running","Health":"healthy"}
{"Name":"trailmq-frontend","Service":"frontend","State":"running","Health":""}`

	for name, input := range map[string]string{"array": array, "ndjson": ndjson} {
		t.Run(name, func(t *testing.T) {
			services, err := parsePS(input)
			if err != nil {
				t.Fatal(err)
			}
			if len(services) != 2 {
				t.Fatalf("got %d services, want 2", len(services))
			}
			if services[0].Service != "backend" || !services[0].Healthy() {
				t.Errorf("backend not read correctly: %+v", services[0])
			}
		})
	}
}

func TestParsePSOnAStoppedStack(t *testing.T) {
	services, err := parsePS("")
	if err != nil {
		t.Fatal(err)
	}
	if len(services) != 0 {
		t.Errorf("got %d services from empty output, want 0", len(services))
	}
}

func TestHealthySemantics(t *testing.T) {
	cases := []struct {
		name    string
		service Service
		healthy bool
	}{
		// A service with a healthcheck is healthy only when it passes.
		{"healthcheck passing", Service{State: "running", Health: "healthy"}, true},
		{"healthcheck starting", Service{State: "running", Health: "starting"}, false},
		{"healthcheck failing", Service{State: "running", Health: "unhealthy"}, false},
		// A service that declares no healthcheck reports an empty Health, and
		// running is then the strongest statement available. Treating that as
		// unhealthy would make waiting for the stack time out forever, because
		// the frontend never reports a health state.
		{"no healthcheck, running", Service{State: "running"}, true},
		{"no healthcheck, exited", Service{State: "exited", ExitCode: 1}, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tc.service.Healthy(); got != tc.healthy {
				t.Errorf("Healthy() = %v, want %v", got, tc.healthy)
			}
		})
	}
}

func TestStatusExplainsWhyAServiceIsNotRunning(t *testing.T) {
	s := Service{State: "exited", ExitCode: 137}
	if got, want := s.Status(), "exited (exit 137)"; got != want {
		t.Errorf("Status() = %q, want %q", got, want)
	}
}

// Compose names a project after the recipe folder, so two TrailMQ
// installations — a clone and an extracted bundle — produce the same project
// name. Without this check, starting one silently recreates the other's
// containers against the wrong data and the other evaluation just disappears.
func TestForeignWorkingDirsDetectsAnotherInstallation(t *testing.T) {
	ours := "/home/user/TrailMQ/recipes/secure-mqtt-core"

	conflicts := foreignWorkingDirs(ours, map[string]string{
		"trailmq-backend":  "/home/user/Downloads/TrailMQ-Evaluation-3.1.0/recipes/secure-mqtt-core",
		"trailmq-frontend": "/home/user/Downloads/TrailMQ-Evaluation-3.1.0/recipes/secure-mqtt-core",
	})
	if len(conflicts) != 2 {
		t.Fatalf("got %d conflicts, want 2: %v", len(conflicts), conflicts)
	}
	// The message has to name where the other stack came from, or the user
	// cannot tell which window to go and stop.
	for _, c := range conflicts {
		if !strings.Contains(c, "Downloads") {
			t.Errorf("conflict does not say where the container came from: %q", c)
		}
	}
}

func TestForeignWorkingDirsAcceptsOurOwnContainers(t *testing.T) {
	ours := "/home/user/TrailMQ/recipes/secure-mqtt-core"

	// Our own stack, a trailing separator, and a container with no working-dir
	// label must all be treated as ours. Reporting those would make start
	// refuse on every normal restart.
	conflicts := foreignWorkingDirs(ours, map[string]string{
		"trailmq-backend":  ours,
		"trailmq-frontend": ours + "/",
		"trailmq-legacy":   "",
	})
	if len(conflicts) != 0 {
		t.Errorf("start would refuse on its own containers: %v", conflicts)
	}
}

func TestProjectNameMatchesComposeNormalisation(t *testing.T) {
	for input, want := range map[string]string{
		"/home/user/TrailMQ/recipes/secure-mqtt-core":       "secure-mqtt-core",
		`C:\Program Files\TrailMQ\recipes\secure-mqtt-core`: "secure-mqtt-core",
	} {
		if got := ProjectName(input); got != want {
			t.Errorf("ProjectName(%q) = %q, want %q", input, got, want)
		}
	}
}
