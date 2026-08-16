package contract

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The shapes both readers must accept, and both must refuse. These cases are
// the agreement between this parser and scripts/release-contract.sh; the
// cross-check further down runs the shell reader against the same inputs where
// bash is available, so the two cannot drift apart unnoticed.
var cases = []struct {
	name  string
	input string
	ok    bool
	want  map[string]string
}{
	{
		name:  "nested maps and scalars",
		input: "version: 3.1.0\nruntime:\n  backend: 3.1.0\n  frontend: 3.1.0\n",
		ok:    true,
		want: map[string]string{
			"version":          "3.1.0",
			"runtime.backend":  "3.1.0",
			"runtime.frontend": "3.1.0",
		},
	},
	{
		name:  "three levels",
		input: "public_surfaces:\n  website:\n    download: required\n",
		ok:    true,
		want:  map[string]string{"public_surfaces.website.download": "required"},
	},
	{
		name:  "null track",
		input: "distribution:\n  launcher: null\n",
		ok:    true,
		want:  map[string]string{"distribution.launcher": "null"},
	},
	{
		name:  "comments and blank lines",
		input: "# leading\n\nversion: 3.1.0  # trailing\n",
		ok:    true,
		want:  map[string]string{"version": "3.1.0"},
	},
	{
		name:  "quoted scalar",
		input: "version: \"3.1.0\"\n",
		ok:    true,
		want:  map[string]string{"version": "3.1.0"},
	},
	{
		name:  "value containing a colon",
		input: "common:\n  url: https://trailmq.com\n",
		ok:    true,
		want:  map[string]string{"common.url": "https://trailmq.com"},
	},
	{name: "odd indentation", input: "runtime:\n   backend: 3.1.0\n", ok: false},
	{name: "tab indentation", input: "runtime:\n\tbackend: 3.1.0\n", ok: false},
	{name: "child under a leaf", input: "version: 3.1.0\n  backend: 3.1.0\n", ok: false},
	{name: "list item", input: "runtime:\n  - backend\n", ok: false},
	{name: "not a key", input: "this is not yaml\n", ok: false},
}

func TestParse(t *testing.T) {
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, err := parse(strings.NewReader(tc.input), "test.yaml")
			if tc.ok && err != nil {
				t.Fatalf("expected the shape to be accepted, got: %v", err)
			}
			if !tc.ok {
				if err == nil {
					t.Fatalf("expected the shape to be refused, but it parsed")
				}
				// A refusal has to say where, or it cannot be acted on.
				if !strings.Contains(err.Error(), "test.yaml:") {
					t.Errorf("refusal does not name a line: %v", err)
				}
				return
			}
			for k, want := range tc.want {
				got, ok := c.Get(k)
				if !ok {
					t.Errorf("missing key %q", k)
					continue
				}
				if got != want {
					t.Errorf("%s = %q, want %q", k, got, want)
				}
			}
		})
	}
}

// The Go reader and the shell reader must agree on every case above. Without
// this, the launcher and the distribution gate could disagree about what a
// release contains — which is the one thing the contract exists to rule out.
func TestAgreesWithShellReader(t *testing.T) {
	reader := repoPath(t, "scripts", "release-contract.sh")
	if _, err := os.Stat(reader); err != nil {
		t.Skip("shell reader not present")
	}
	if _, err := exec.LookPath("bash"); err != nil {
		t.Skip("bash not available on this platform")
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			file := filepath.Join(t.TempDir(), "release.yaml")
			if err := os.WriteFile(file, []byte(tc.input), 0o644); err != nil {
				t.Fatal(err)
			}

			cmd := exec.Command("bash", reader, "flatten", file)
			cmd.Env = append(os.Environ(), "TRAILMQ_RELEASE_CONTRACT="+file)
			out, err := cmd.Output()
			shellAccepted := err == nil

			if shellAccepted != tc.ok {
				t.Fatalf("shell reader accepted=%v, Go reader accepts=%v — the readers disagree",
					shellAccepted, tc.ok)
			}
			if !tc.ok {
				return
			}

			got := map[string]string{}
			for _, line := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
				if line == "" {
					continue
				}
				k, v, found := strings.Cut(line, "\t")
				if !found {
					t.Fatalf("shell reader emitted an unexpected line: %q", line)
				}
				got[k] = v
			}
			for k, want := range tc.want {
				if got[k] != want {
					t.Errorf("shell reader has %s = %q, Go reader expects %q", k, got[k], want)
				}
			}
		})
	}
}

// The launcher must report the release the repository actually declares.
func TestRepositoryContract(t *testing.T) {
	path := repoPath(t, FileName)
	c, err := Load(path)
	if err != nil {
		t.Fatalf("the repository contract does not parse: %v", err)
	}

	version, err := c.Version()
	if err != nil {
		t.Fatal(err)
	}
	for _, key := range []string{"runtime.backend", "runtime.frontend"} {
		got, err := c.MustGet(key)
		if err != nil {
			t.Fatal(err)
		}
		if got != version {
			t.Errorf("%s = %q, want the release version %q", key, got, version)
		}
	}
}

func TestFindPrefersExplicitPath(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, FileName)
	if err := os.WriteFile(file, []byte("version: 9.9.9\n"), 0o644); err != nil {
		t.Fatal(err)
	}

	t.Setenv("TRAILMQ_RELEASE_CONTRACT", file)
	got, err := Find()
	if err != nil {
		t.Fatal(err)
	}
	if got != file {
		t.Errorf("Find() = %q, want %q", got, file)
	}

	// A path that is set but wrong must be reported, never silently ignored in
	// favour of some other contract found nearby.
	t.Setenv("TRAILMQ_RELEASE_CONTRACT", filepath.Join(dir, "absent.yaml"))
	if _, err := Find(); err == nil {
		t.Error("Find() accepted a TRAILMQ_RELEASE_CONTRACT that does not exist")
	}
}

func repoPath(t *testing.T, parts ...string) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Join(append([]string{root}, parts...)...)
}
