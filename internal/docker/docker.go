// Package docker probes the container runtime the evaluation depends on.
//
// Everything here is read-only: it asks whether Docker is installed, running
// and new enough, and never starts, stops or pulls anything. The point is to
// turn the runtime's own error strings into something a person can act on.
// "error during connect: ... The system cannot find the file specified" is a
// true statement about a named pipe and a useless statement to the automation
// engineer who simply has not started Docker Desktop yet.
package docker

import (
	"context"
	"os/exec"
	"strings"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/platform"
)

// probeTimeout bounds each probe. A Docker CLI talking to an engine that is
// starting up can block for a long time, and a diagnostic command that hangs
// is worse than one that reports "not ready yet".
const probeTimeout = 20 * time.Second

type Status struct {
	// CLIPath is empty when the docker command is not on PATH.
	CLIPath string
	// ClientVersion is reported even when the engine is unreachable — the CLI
	// answers on its own.
	ClientVersion string

	EngineReachable bool
	ServerVersion   string
	// EngineError is the runtime's own message, kept verbatim for the detail
	// line. Explain() turns it into the sentence a user acts on.
	EngineError string

	ComposeAvailable bool
	ComposeVersion   string
}

func (s Status) CLIFound() bool { return s.CLIPath != "" }

// Ready reports whether the environment can run the evaluation stack.
func (s Status) Ready() bool {
	return s.CLIFound() && s.EngineReachable && s.ComposeAvailable
}

// Probe inspects the local Docker installation.
func Probe(ctx context.Context) Status {
	var s Status

	path, err := exec.LookPath("docker")
	if err != nil {
		return s
	}
	s.CLIPath = path

	s.ClientVersion = run(ctx, "docker", "version", "--format", "{{.Client.Version}}")

	// `docker info` is the probe that actually contacts the engine; the client
	// answers `docker version` happily with nothing running behind it.
	out, errOut, err := runFull(ctx, "docker", "info", "--format", "{{.ServerVersion}}")
	if err == nil && out != "" {
		s.EngineReachable = true
		s.ServerVersion = out
	} else {
		s.EngineError = firstLine(errOut)
		if s.EngineError == "" && err != nil {
			s.EngineError = err.Error()
		}
	}

	if v := run(ctx, "docker", "compose", "version", "--short"); v != "" {
		s.ComposeAvailable = true
		s.ComposeVersion = v
	}

	return s
}

// Explain turns the probe into a problem statement and a remedy, or returns
// ok=true when there is nothing to fix. The remedy names the product the user
// has on their machine and the command that re-runs the check.
func (s Status) Explain(p platform.Info) (problem, remedy string, ok bool) {
	switch {
	case !s.CLIFound():
		if p.IsWindows() {
			return "Docker is not installed, or not on PATH",
				"Install Docker Desktop from https://docs.docker.com/desktop/install/windows-install/\n" +
					"and restart your terminal so the docker command becomes available.", false
		}
		return "Docker is not installed, or not on PATH",
			"Install Docker 20.10 or newer, then run 'trailmq doctor' again.", false

	case !s.EngineReachable:
		product := p.DockerProduct()
		if p.IsWindows() || p.WSL {
			return product + " is installed but the Docker engine is not running",
				"Start " + product + ", wait until it reports that the engine is running,\n" +
					"then run 'trailmq doctor' again.", false
		}
		if p.OS == "darwin" {
			return product + " is installed but the Docker engine is not running",
				"Start " + product + " from Applications and run 'trailmq doctor' again.", false
		}
		return "The Docker engine is not reachable",
			"Start it with 'sudo systemctl start docker'. If it is running, your user may\n" +
				"not be in the 'docker' group — see https://docs.docker.com/engine/install/linux-postinstall/", false

	case !s.ComposeAvailable:
		return "Docker Compose v2 is not available",
			"TrailMQ needs the Compose plugin, not the standalone docker-compose script.\n" +
				"Check with 'docker compose version'; on Linux install the docker-compose-plugin package.", false
	}

	return "", "", true
}

func run(ctx context.Context, name string, args ...string) string {
	out, _, err := runFull(ctx, name, args...)
	if err != nil {
		return ""
	}
	return out
}

func runFull(ctx context.Context, name string, args ...string) (stdout, stderr string, err error) {
	ctx, cancel := context.WithTimeout(ctx, probeTimeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, name, args...)
	var outBuf, errBuf strings.Builder
	cmd.Stdout = &outBuf
	cmd.Stderr = &errBuf
	err = cmd.Run()
	return strings.TrimSpace(outBuf.String()), strings.TrimSpace(errBuf.String()), err
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return strings.TrimSpace(s[:i])
	}
	return strings.TrimSpace(s)
}
