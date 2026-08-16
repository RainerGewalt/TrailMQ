// Package compose drives the evaluation stack through the Docker CLI.
//
// The execution boundary is `docker compose`, deliberately, rather than the
// Docker Go SDK. The SDK would pull a substantial dependency tree into a
// binary whose whole appeal is that it has none, and it would make the
// launcher responsible for reimplementing what Compose already does with the
// recipe's own file. Shelling out to the CLI the user already has installed
// keeps the launcher small and keeps the recipe the single description of the
// stack.
//
// This is not a shell dependency: docker is invoked directly, with an argument
// vector, never through sh, bash or cmd.
package compose

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

// Project runs Compose commands for one recipe directory.
type Project struct {
	// Dir is the directory holding docker-compose.yaml. Compose resolves the
	// recipe's relative bind mounts against it.
	Dir string
	// Env carries TRAILMQ_* overrides. Compose reads a .env file next to the
	// Compose file, but TrailMQ's lives at the installation root, so the
	// launcher resolves it and passes the result down.
	Env []string
}

// Service is one container as Compose reports it.
type Service struct {
	Name       string      `json:"Name"`
	Service    string      `json:"Service"`
	State      string      `json:"State"`
	Health     string      `json:"Health"`
	ExitCode   int         `json:"ExitCode"`
	Publishers []Publisher `json:"Publishers"`
}

type Publisher struct {
	URL           string `json:"URL"`
	TargetPort    int    `json:"TargetPort"`
	PublishedPort int    `json:"PublishedPort"`
	Protocol      string `json:"Protocol"`
}

// Running reports whether the container is up.
func (s Service) Running() bool { return strings.EqualFold(s.State, "running") }

// Healthy reports whether a service with a healthcheck has passed it. A
// service that declares no healthcheck reports an empty Health, and running is
// then the strongest statement available.
func (s Service) Healthy() bool {
	if s.Health == "" {
		return s.Running()
	}
	return strings.EqualFold(s.Health, "healthy")
}

// Status renders the service state for a person.
func (s Service) Status() string {
	if s.Health != "" {
		return fmt.Sprintf("%s (%s)", s.State, s.Health)
	}
	if !s.Running() && s.ExitCode != 0 {
		return fmt.Sprintf("%s (exit %d)", s.State, s.ExitCode)
	}
	return s.State
}

func (p Project) command(ctx context.Context, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, "docker", append([]string{"compose"}, args...)...)
	cmd.Dir = p.Dir
	cmd.Env = append(os.Environ(), p.Env...)
	return cmd
}

// run executes a Compose command, returning the runtime's own stderr on
// failure. Compose messages are usually precise about what went wrong, so they
// are surfaced rather than replaced.
func (p Project) run(ctx context.Context, stream bool, args ...string) (string, error) {
	cmd := p.command(ctx, args...)

	var out, errBuf bytes.Buffer
	if stream {
		// Pulling and starting take long enough that silence reads as a hang.
		cmd.Stdout = os.Stdout
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stdout = &out
		cmd.Stderr = &errBuf
	}

	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(errBuf.String())
		if msg == "" {
			return "", err
		}
		return "", fmt.Errorf("%s", msg)
	}
	return out.String(), nil
}

// Up starts the stack in the background.
func (p Project) Up(ctx context.Context) error {
	_, err := p.run(ctx, true, "up", "-d", "--remove-orphans")
	return err
}

// Pull fetches the images the recipe pins.
func (p Project) Pull(ctx context.Context) error {
	_, err := p.run(ctx, true, "pull")
	return err
}

// Down stops the stack. Volumes are never removed here: the evaluation's
// databases, certificates and audit archive are the user's data, and a stop
// command must not be able to destroy them.
func (p Project) Down(ctx context.Context) error {
	_, err := p.run(ctx, true, "down", "--remove-orphans")
	return err
}

// PS reports the current containers.
func (p Project) PS(ctx context.Context) ([]Service, error) {
	out, err := p.run(ctx, false, "ps", "--all", "--format", "json")
	if err != nil {
		return nil, err
	}
	return parsePS(out)
}

// parsePS accepts both shapes Compose has emitted for --format json: a single
// JSON array, and one JSON object per line. Which one appears depends on the
// Compose version, and an evaluator's version is not something the launcher
// gets to choose.
func parsePS(out string) ([]Service, error) {
	trimmed := strings.TrimSpace(out)
	if trimmed == "" {
		return nil, nil
	}

	if strings.HasPrefix(trimmed, "[") {
		var services []Service
		if err := json.Unmarshal([]byte(trimmed), &services); err != nil {
			return nil, fmt.Errorf("could not read the container list: %w", err)
		}
		return services, nil
	}

	var services []Service
	for _, line := range strings.Split(trimmed, "\n") {
		line = strings.TrimSpace(line)
		if line == "" {
			continue
		}
		var s Service
		if err := json.Unmarshal([]byte(line), &s); err != nil {
			return nil, fmt.Errorf("could not read the container list: %w", err)
		}
		services = append(services, s)
	}
	return services, nil
}

// ForeignContainers reports containers holding TrailMQ's reserved names that
// belong to a different Compose project.
//
// These are the leftovers of an earlier setup. Compose will not adopt them and
// Docker will not allow two containers to share a name, so the stack fails to
// start with an error about the name rather than about the cause.
func ForeignContainers(ctx context.Context, project string) ([]string, error) {
	reserved := []string{"trailmq-backend", "trailmq-frontend", "trailmq-reverse-proxy"}

	var foreign []string
	for _, name := range reserved {
		cmd := exec.CommandContext(ctx, "docker", "container", "inspect",
			"--format", "{{ index .Config.Labels \"com.docker.compose.project\" }}", name)
		var out bytes.Buffer
		cmd.Stdout = &out
		if err := cmd.Run(); err != nil {
			continue // no such container, which is the normal case
		}
		owner := strings.TrimSpace(out.String())
		if owner != project {
			if owner == "" {
				owner = "untracked"
			}
			foreign = append(foreign, fmt.Sprintf("%s (compose project: %s)", name, owner))
		}
	}
	return foreign, nil
}

// HijackedProject reports containers that belong to this Compose project name
// but were started from a different directory.
//
// Compose derives the project name from the directory's base name, so two
// TrailMQ installations — a clone and an extracted bundle, or a bundle in
// Downloads and another in Documents — both produce the project
// "secure-mqtt-core". Compose then treats the other installation's containers
// as belonging to this one and recreates them, pointing them at this
// installation's volumes. The other evaluation loses its running stack, with
// no error anywhere: the operation succeeds, on the wrong containers.
//
// This is checked before starting, because afterwards it has already happened.
func HijackedProject(ctx context.Context, dir string) ([]string, error) {
	project := ProjectName(dir)

	cmd := exec.CommandContext(ctx, "docker", "ps", "--all",
		"--filter", "label=com.docker.compose.project="+project,
		"--format", "{{.Names}}")
	var out bytes.Buffer
	cmd.Stdout = &out
	if err := cmd.Run(); err != nil {
		// Docker not answering is diagnosed elsewhere; this check must not be
		// the thing that reports it.
		return nil, nil
	}

	owners := map[string]string{}
	for _, name := range strings.Fields(out.String()) {
		inspect := exec.CommandContext(ctx, "docker", "container", "inspect",
			"--format", "{{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}", name)
		var dirOut bytes.Buffer
		inspect.Stdout = &dirOut
		if err := inspect.Run(); err != nil {
			continue
		}
		owners[name] = strings.TrimSpace(dirOut.String())
	}

	return foreignWorkingDirs(dir, owners), nil
}

// foreignWorkingDirs is the decision separated from the Docker calls, so the
// rule can be tested without a daemon.
func foreignWorkingDirs(ours string, containers map[string]string) []string {
	var conflicts []string
	for name, workingDir := range containers {
		if workingDir == "" || sameDir(workingDir, ours) {
			continue
		}
		conflicts = append(conflicts, fmt.Sprintf("%s (started from %s)", name, workingDir))
	}
	sort.Strings(conflicts)
	return conflicts
}

func sameDir(a, b string) bool {
	clean := func(s string) string {
		s = filepath.Clean(s)
		if resolved, err := filepath.EvalSymlinks(s); err == nil {
			s = resolved
		}
		return s
	}
	return clean(a) == clean(b)
}

// ProjectName is the name Compose derives from a directory, which is what the
// reserved-name check has to compare against.
func ProjectName(dir string) string {
	base := strings.ToLower(dir[strings.LastIndexAny(dir, `/\`)+1:])
	var b strings.Builder
	for _, r := range base {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '_', r == '-':
			b.WriteRune(r)
		}
	}
	return b.String()
}
