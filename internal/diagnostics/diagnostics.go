// Package diagnostics implements `trailmq doctor`.
//
// A diagnosis is only useful if it ends in an action. Every check that can
// fail therefore carries a remedy written as an instruction, not as a
// restatement of the error, and the report distinguishes what blocks an
// evaluation from what is merely worth knowing.
package diagnostics

import (
	"context"

	"github.com/RainerGewalt/TrailMQ/internal/contract"
	"github.com/RainerGewalt/TrailMQ/internal/docker"
	"github.com/RainerGewalt/TrailMQ/internal/endpoints"
	"github.com/RainerGewalt/TrailMQ/internal/platform"
)

type Status int

const (
	Pass Status = iota
	Warn
	Fail
)

type Check struct {
	Name   string
	Status Status
	// Detail states what was found.
	Detail string
	// Remedy states what to do about it, and is empty when there is nothing
	// to do.
	Remedy string
}

type Report struct {
	Checks []Check
}

// Blocked reports whether anything found would stop an evaluation from
// starting. Warnings do not block: a port already in use is usually TrailMQ
// itself, and refusing to proceed over that would be wrong.
func (r Report) Blocked() bool {
	for _, c := range r.Checks {
		if c.Status == Fail {
			return true
		}
	}
	return false
}

func (r *Report) add(c Check) { r.Checks = append(r.Checks, c) }

// Run performs every check. root is the TrailMQ directory — the one holding
// release.yaml — and may be empty when no contract was found.
func Run(ctx context.Context, root string, c *contract.Contract) Report {
	var r Report
	p := platform.Detect()

	// --- platform -----------------------------------------------------------
	platformCheck := Check{
		Name:   "Platform",
		Status: Pass,
		Detail: p.String(),
	}
	// TrailMQ runtime images are published for linux/amd64. Saying so here
	// costs one line and prevents an evaluation that is mysteriously slow from
	// being read as a product problem.
	if p.RuntimeArch() != "linux/amd64" {
		platformCheck.Status = Warn
		platformCheck.Detail = p.String() + " — TrailMQ images are published for linux/amd64"
		platformCheck.Remedy = "The stack will run under emulation on this architecture.\n" +
			"It works, but expect slower startup than the documented timings."
	}
	r.add(platformCheck)

	// --- release contract ---------------------------------------------------
	switch {
	case c == nil:
		r.add(Check{
			Name:   "Release contract",
			Status: Fail,
			Detail: "release.yaml was not found",
			Remedy: "Run trailmq from the TrailMQ directory, or set TRAILMQ_ROOT to it.\n" +
				"The launcher reads the release it belongs to from that file.",
		})
	default:
		version, err := c.Version()
		if err != nil {
			r.add(Check{
				Name:   "Release contract",
				Status: Fail,
				Detail: err.Error(),
				Remedy: "The contract is readable but declares no version. Reinstall the\n" +
					"evaluation package rather than editing release.yaml by hand.",
			})
		} else {
			r.add(Check{
				Name:   "Release contract",
				Status: Pass,
				Detail: "TrailMQ " + version + " (" + c.Path + ")",
			})
		}
	}

	// --- container runtime --------------------------------------------------
	status := docker.Probe(ctx)
	problem, remedy, _ := status.Explain(p)

	switch {
	case !status.CLIFound():
		r.add(Check{Name: "Docker", Status: Fail, Detail: problem, Remedy: remedy})
	default:
		r.add(Check{
			Name:   "Docker",
			Status: Pass,
			Detail: "client " + orUnknown(status.ClientVersion) + " (" + status.CLIPath + ")",
		})

		engine := Check{Name: "Docker engine"}
		if status.EngineReachable {
			engine.Status = Pass
			engine.Detail = "running, server " + orUnknown(status.ServerVersion)
		} else {
			engine.Status = Fail
			engine.Detail = problem
			engine.Remedy = remedy
			if status.EngineError != "" {
				engine.Detail = problem + "\nReported by Docker: " + status.EngineError
			}
		}
		r.add(engine)

		compose := Check{Name: "Docker Compose"}
		if status.ComposeAvailable {
			compose.Status = Pass
			compose.Detail = "v2 available, " + orUnknown(status.ComposeVersion)
		} else if status.EngineReachable {
			// Only meaningful once the engine answers; otherwise this repeats
			// the engine failure in different words.
			compose.Status = Fail
			compose.Detail = problem
			compose.Remedy = remedy
		} else {
			compose.Status = Warn
			compose.Detail = "not checked — the engine has to answer first"
		}
		r.add(compose)
	}

	// --- ports --------------------------------------------------------------
	e := endpoints.Load(root)
	for _, port := range []struct {
		name  string
		value string
		env   string
	}{
		{"Web UI port", e.HTTPPort, "TRAILMQ_HTTP_PORT"},
		{"MQTT TLS port", e.MQTTTLSPort, "TRAILMQ_MQTT_TLS_PORT"},
	} {
		check := Check{Name: port.name, Status: Pass, Detail: port.value + " is free"}
		if endpoints.InUse(port.value) {
			check.Status = Warn
			check.Detail = port.value + " is already in use"
			check.Remedy = "If that is TrailMQ, this is expected. If it is another service,\n" +
				"set " + port.env + " to a free port before starting."
		}
		r.add(check)
	}

	return r
}

func orUnknown(s string) string {
	if s == "" {
		return "version unknown"
	}
	return s
}
