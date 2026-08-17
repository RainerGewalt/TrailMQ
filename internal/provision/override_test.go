package provision

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/RainerGewalt/TrailMQ/internal/layout"
)

// A portable copy keeps everything in one folder, and the recipe's own
// relative mounts are already correct. Writing an override there would be a
// file with nothing to say.
func TestNoOverrideWhenNothingIsSeparated(t *testing.T) {
	l := layout.Resolve(filepath.Join(t.TempDir(), "release.yaml"))
	r := l.Recipe("secure-mqtt-core")

	path, err := EnsureComposeOverride(l, r)
	if err != nil {
		t.Fatal(err)
	}
	if path != "" {
		t.Errorf("EnsureComposeOverride wrote %q for a portable layout", path)
	}
}

func TestOverrideRedirectsEveryWritableMount(t *testing.T) {
	install := t.TempDir()
	state := t.TempDir()
	t.Setenv("TRAILMQ_STATE_DIR", filepath.Join(state, "recipes"))

	l := layout.Resolve(filepath.Join(install, "release.yaml"))
	if !l.Separated() {
		t.Fatal("the layout should be separated once state points elsewhere")
	}

	r := l.Recipe("secure-mqtt-core")
	path, err := EnsureComposeOverride(l, r)
	if err != nil {
		t.Fatal(err)
	}
	if path == "" {
		t.Fatal("no override was written for a separated layout")
	}

	body, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	text := string(body)

	// Every directory the stack writes into has to move with the user's data.
	// One left behind would write into the program directory, which an
	// installed copy must never do.
	for _, target := range []string{
		"/app/data", "/app/logs", "/app/audit-archive", "/app/certs", "/app/secrets",
	} {
		if !strings.Contains(text, target) {
			t.Errorf("the override does not redirect %s", target)
		}
	}

	// Product assets stay with the installation: they are shipped, read-only,
	// and not the user's to keep.
	if strings.Contains(text, "config.yaml") || strings.Contains(text, "nginx.conf") {
		t.Error("the override moves a read-only product asset into the state directory")
	}

	// Compose reads these as YAML scalars, where a Windows backslash would be
	// an escape rather than a path separator.
	if strings.Contains(text, `\`) {
		t.Error("the override contains backslashes, which will not survive YAML on Windows")
	}
}

func TestOverrideIsRewrittenRatherThanAppended(t *testing.T) {
	install := t.TempDir()
	t.Setenv("TRAILMQ_STATE_DIR", filepath.Join(t.TempDir(), "recipes"))

	l := layout.Resolve(filepath.Join(install, "release.yaml"))
	r := l.Recipe("secure-mqtt-core")

	first, err := EnsureComposeOverride(l, r)
	if err != nil {
		t.Fatal(err)
	}
	before := read(t, first)

	second, err := EnsureComposeOverride(l, r)
	if err != nil {
		t.Fatal(err)
	}
	if second != first {
		t.Errorf("the override moved from %q to %q", first, second)
	}
	// It is regenerated on every command, so a second run must produce the
	// same file rather than accumulate.
	if after := read(t, second); after != before {
		t.Error("regenerating the override changed its content")
	}
}
