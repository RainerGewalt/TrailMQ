// Package layout resolves where TrailMQ's files live.
//
// The launcher must not assume it is running inside a repository checkout. A
// Windows evaluator will eventually install TrailMQ, not clone it, and at that
// point three things that happen to share a directory today stop doing so:
//
//	installation   the launcher and the release contract
//	assets         compose files and configuration templates, read-only
//	state          certificates, credentials, databases, logs — the user's data
//
// Every path in the launcher is derived here rather than composed inline, so
// the installed layout becomes a change to this package instead of a search
// for "../../recipes" across the codebase.
//
// Today assets and state resolve to the same directory. That is not an
// oversight: the recipe's Compose file bind-mounts ./data, ./certs and
// ./secrets relative to itself, so separating them requires a Compose override
// that ships with the installed layout. Modelling them as distinct now is what
// makes that change small later.
package layout

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// DefaultRecipe is the recipe a first run selects. The launcher does not offer
// a choice: there is exactly one available recipe, and a menu with one item is
// a question that wastes the reader's attention.
const DefaultRecipe = "secure-mqtt-core"

type Layout struct {
	// Install holds the release contract and, once packaged, the launcher.
	Install string
	// Assets holds read-only inputs: Compose files, configuration, nginx.
	Assets string
	// State holds everything generated on this machine.
	State string
	// Runtime holds launcher bookkeeping, such as the active recipe.
	Runtime string
}

// Resolve derives the layout from the release contract's location, which is
// the one file guaranteed to sit at the installation root.
func Resolve(contractPath string) Layout {
	install := filepath.Dir(contractPath)

	l := Layout{
		Install: install,
		Assets:  filepath.Join(install, "recipes"),
		State:   filepath.Join(install, "recipes"),
		Runtime: filepath.Join(install, ".trailmq"),
	}

	// An explicit state directory is honoured now so the installed layout has
	// somewhere to point without this package changing shape again.
	if dir := os.Getenv("TRAILMQ_STATE_DIR"); dir != "" {
		l.State = dir
	}
	return l
}

// Recipe describes one runnable stack.
type Recipe struct {
	Name string
	// Assets is the directory Compose runs in.
	Assets string
	// State is the root of everything this recipe generates.
	State string
}

func (l Layout) Recipe(name string) Recipe {
	return Recipe{
		Name:   name,
		Assets: filepath.Join(l.Assets, name),
		State:  filepath.Join(l.State, name),
	}
}

// Exists reports whether the recipe's assets are actually installed.
func (r Recipe) Exists() bool {
	st, err := os.Stat(r.ComposeFile())
	return err == nil && !st.IsDir()
}

func (r Recipe) ComposeFile() string { return filepath.Join(r.Assets, "docker-compose.yaml") }
func (r Recipe) ConfigFile() string  { return filepath.Join(r.Assets, "config.yaml") }

func (r Recipe) CertsDir() string   { return filepath.Join(r.State, "certs") }
func (r Recipe) SecretsDir() string { return filepath.Join(r.State, "secrets") }
func (r Recipe) DataDir() string    { return filepath.Join(r.State, "data") }
func (r Recipe) LogsDir() string    { return filepath.Join(r.State, "logs") }
func (r Recipe) AuditDir() string   { return filepath.Join(r.State, "audit-archive") }

// StateDirs are the directories Compose bind-mounts. They must exist before
// the stack starts: Docker would otherwise create them as root-owned
// directories, which is a permission problem the user did not cause and cannot
// easily diagnose.
func (r Recipe) StateDirs() []string {
	return []string{r.DataDir(), r.LogsDir(), r.AuditDir(), r.CertsDir(), r.SecretsDir()}
}

// EnsureStateDirs creates the bind-mount targets.
func (r Recipe) EnsureStateDirs() error {
	for _, dir := range r.StateDirs() {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("could not create %s: %w", dir, err)
		}
	}
	return nil
}

// ErrNoActiveRecipe reports that nothing has been set up yet.
var ErrNoActiveRecipe = errors.New("no active recipe")

func (l Layout) activeRecipeFile() string { return filepath.Join(l.Runtime, "active-recipe") }

// ActiveRecipe returns the recipe the last setup selected.
//
// The file is shared with the shell launcher on purpose. While both exist,
// they have to agree on what is running, or `trailmq status` would report on a
// different stack than `./trailmq quickstart` started.
func (l Layout) ActiveRecipe() (string, error) {
	b, err := os.ReadFile(l.activeRecipeFile())
	if err != nil {
		if os.IsNotExist(err) {
			return "", ErrNoActiveRecipe
		}
		return "", err
	}
	name := strings.TrimSpace(string(b))
	if name == "" {
		return "", ErrNoActiveRecipe
	}
	if !l.Recipe(name).Exists() {
		return "", fmt.Errorf("active recipe %q is not installed in %s", name, l.Assets)
	}
	return name, nil
}

// SetActiveRecipe records the selection.
func (l Layout) SetActiveRecipe(name string) error {
	if err := os.MkdirAll(l.Runtime, 0o755); err != nil {
		return err
	}
	return os.WriteFile(l.activeRecipeFile(), []byte(name+"\n"), 0o644)
}
