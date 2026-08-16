package layout

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestResolveDerivesEverythingFromTheContract(t *testing.T) {
	install := t.TempDir()
	l := Resolve(filepath.Join(install, "release.yaml"))

	if l.Install != install {
		t.Errorf("Install = %q, want %q", l.Install, install)
	}
	// The launcher must never reach outside the installation. A path that
	// escaped it would write into the user's working directory, wherever that
	// happens to be when they double-click a shortcut.
	for name, dir := range map[string]string{
		"Assets":  l.Assets,
		"State":   l.State,
		"Runtime": l.Runtime,
	} {
		rel, err := filepath.Rel(install, dir)
		if err != nil || rel == ".." || filepath.IsAbs(rel) || len(rel) > 1 && rel[:2] == ".." {
			t.Errorf("%s (%q) is outside the installation root", name, dir)
		}
	}
}

func TestStateDirectoryCanBeRelocated(t *testing.T) {
	install := t.TempDir()
	state := t.TempDir()
	t.Setenv("TRAILMQ_STATE_DIR", state)

	l := Resolve(filepath.Join(install, "release.yaml"))
	if l.State != state {
		t.Fatalf("State = %q, want %q", l.State, state)
	}

	// Assets stay with the installation: they are shipped, not generated.
	if l.Assets == state {
		t.Error("relocating state also moved the read-only assets")
	}

	r := l.Recipe("secure-mqtt-core")
	if got, want := r.CertsDir(), filepath.Join(state, "secure-mqtt-core", "certs"); got != want {
		t.Errorf("CertsDir() = %q, want %q", got, want)
	}
	if got, want := r.ComposeFile(), filepath.Join(l.Assets, "secure-mqtt-core", "docker-compose.yaml"); got != want {
		t.Errorf("ComposeFile() = %q, want %q", got, want)
	}
}

func TestActiveRecipeRoundTrip(t *testing.T) {
	install := t.TempDir()
	l := Resolve(filepath.Join(install, "release.yaml"))

	if _, err := l.ActiveRecipe(); !errors.Is(err, ErrNoActiveRecipe) {
		t.Fatalf("ActiveRecipe() on a fresh install = %v, want ErrNoActiveRecipe", err)
	}

	installRecipe(t, l, "secure-mqtt-core")
	if err := l.SetActiveRecipe("secure-mqtt-core"); err != nil {
		t.Fatal(err)
	}

	got, err := l.ActiveRecipe()
	if err != nil {
		t.Fatal(err)
	}
	if got != "secure-mqtt-core" {
		t.Errorf("ActiveRecipe() = %q, want %q", got, "secure-mqtt-core")
	}
}

// The shell launcher and the binary have to agree on what is running while
// both exist, and they agree through this file.
func TestActiveRecipeUsesTheSameFileAsTheShellLauncher(t *testing.T) {
	install := t.TempDir()
	l := Resolve(filepath.Join(install, "release.yaml"))
	installRecipe(t, l, "secure-mqtt-core")

	// Written the way scripts/common.sh writes it.
	shellPath := filepath.Join(install, ".trailmq", "active-recipe")
	if err := os.MkdirAll(filepath.Dir(shellPath), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(shellPath, []byte("secure-mqtt-core\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	got, err := l.ActiveRecipe()
	if err != nil {
		t.Fatalf("the binary cannot read the shell launcher's selection: %v", err)
	}
	if got != "secure-mqtt-core" {
		t.Errorf("ActiveRecipe() = %q, want %q", got, "secure-mqtt-core")
	}
}

func TestActiveRecipeRejectsARecipeThatIsNotInstalled(t *testing.T) {
	install := t.TempDir()
	l := Resolve(filepath.Join(install, "release.yaml"))
	if err := l.SetActiveRecipe("removed-recipe"); err != nil {
		t.Fatal(err)
	}

	// Reporting on a recipe whose files are gone would produce Compose errors
	// about a missing file instead of naming the actual problem.
	if _, err := l.ActiveRecipe(); err == nil {
		t.Error("ActiveRecipe() accepted a recipe that is not installed")
	}
}

func TestEnsureStateDirsCreatesEveryBindMount(t *testing.T) {
	l := Resolve(filepath.Join(t.TempDir(), "release.yaml"))
	r := l.Recipe("secure-mqtt-core")

	if err := r.EnsureStateDirs(); err != nil {
		t.Fatal(err)
	}
	for _, dir := range r.StateDirs() {
		st, err := os.Stat(dir)
		if err != nil || !st.IsDir() {
			t.Errorf("%s was not created", dir)
		}
	}

	// Compose creates missing bind-mount sources as root-owned directories, so
	// running twice must stay clean rather than error.
	if err := r.EnsureStateDirs(); err != nil {
		t.Errorf("EnsureStateDirs is not idempotent: %v", err)
	}
}

func installRecipe(t *testing.T, l Layout, name string) {
	t.Helper()
	dir := filepath.Join(l.Assets, name)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "docker-compose.yaml"), []byte("services: {}\n"), 0o644); err != nil {
		t.Fatal(err)
	}
}
