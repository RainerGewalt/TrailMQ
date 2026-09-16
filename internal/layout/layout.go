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
	"runtime"
	"strings"
)

// DefaultRecipe is the recipe a first run selects. The launcher does not offer
// a choice: there is exactly one available recipe, and a menu with one item is
// a question that wastes the reader's attention.
const DefaultRecipe = "secure-mqtt-core"

type Layout struct {
	// Mode is how this copy was deployed, which decides whether state lives
	// beside the assets or in the user's own profile.
	Mode Mode
	// Install holds the release contract and, once packaged, the launcher.
	Install string
	// Assets holds read-only inputs: Compose files, configuration, nginx.
	Assets string
	// State holds everything generated on this machine.
	State string
	// Runtime holds launcher bookkeeping, such as the active recipe.
	Runtime string
}

// InstalledMarker sits next to the launcher in an installed copy. The
// installer writes it; a checkout or an extracted archive does not have one.
//
// A marker is used rather than a guess about whether the directory is
// writable. Program Files happens to be writable for an administrator, and a
// launcher that decided where to put the user's certificates based on who
// started it would put them in two different places on the same machine.
const InstalledMarker = ".trailmq-installed"

// Mode is how this copy of TrailMQ was deployed.
type Mode int

const (
	// Portable is a checkout or an extracted archive: everything lives
	// together in one folder the user can delete.
	Portable Mode = iota
	// Installed is a system installation: product assets are read-only and
	// the user's state lives in their own profile.
	Installed
)

func (m Mode) String() string {
	if m == Installed {
		return "installed"
	}
	return "portable"
}

// Resolve derives the layout from the release contract's location, which is
// the one file guaranteed to sit at the installation root.
func Resolve(contractPath string) Layout {
	install := filepath.Dir(contractPath)

	l := Layout{
		Mode:    Portable,
		Install: install,
		Assets:  filepath.Join(install, "recipes"),
		State:   filepath.Join(install, "recipes"),
		Runtime: filepath.Join(install, ".trailmq"),
	}

	if _, err := os.Stat(filepath.Join(install, InstalledMarker)); err == nil {
		// An installation writes nothing into its own program directory. The
		// evaluation's databases, certificates and credentials belong to the
		// user, and putting them under Program Files would make them
		// unwritable for a normal account and invisible when uninstalling.
		l.Mode = Installed
		if data, err := userStateDir(); err == nil {
			l.State = filepath.Join(data, "recipes")
			l.Runtime = filepath.Join(data, "state")
		}
	}

	// An explicit override wins over both, for tests and unusual deployments.
	if dir := os.Getenv("TRAILMQ_STATE_DIR"); dir != "" {
		l.State = dir
		if l.Mode == Installed {
			l.Runtime = filepath.Join(filepath.Dir(dir), "state")
		}
	}
	return l
}

// Separated reports whether state lives outside the installation. When it
// does, the recipe's relative bind mounts no longer point at the user's data
// and Compose needs an override.
func (l Layout) Separated() bool {
	return filepath.Clean(l.Assets) != filepath.Clean(l.State)
}

// userStateDir is where this platform keeps per-user application data.
func userStateDir() (string, error) {
	switch runtime.GOOS {
	case "windows":
		// LOCALAPPDATA rather than the roaming profile: an evaluation's
		// database and container state are machine-local and must not be
		// synchronised onto another machine by a domain profile.
		if dir := os.Getenv("LOCALAPPDATA"); dir != "" {
			return filepath.Join(dir, "TrailMQ"), nil
		}
	case "darwin":
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, "Library", "Application Support", "TrailMQ"), nil
		}
	default:
		if dir := os.Getenv("XDG_DATA_HOME"); dir != "" {
			return filepath.Join(dir, "trailmq"), nil
		}
		if home, err := os.UserHomeDir(); err == nil {
			return filepath.Join(home, ".local", "share", "trailmq"), nil
		}
	}
	return "", errors.New("could not determine a per-user data directory")
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
