package main

import (
	"bytes"
	"go/ast"
	"go/parser"
	"go/token"
	"io/fs"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func exercise(t *testing.T, args ...string) (code int, stdout, stderr string) {
	t.Helper()
	var out, errOut bytes.Buffer
	code = run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

// The contract in this repository is the one the launcher must report. This is
// the same guarantee the distribution gate makes for the shell launcher.
func TestVersionReportsTheReleaseContract(t *testing.T) {
	t.Setenv("TRAILMQ_RELEASE_CONTRACT", repoFile(t, "release.yaml"))
	t.Setenv("NO_COLOR", "1")

	code, stdout, stderr := exercise(t, "version")
	if code != exitOK {
		t.Fatalf("exit %d, stderr: %s", code, stderr)
	}

	want := releaseVersion(t)
	if !strings.Contains(stdout, "TrailMQ "+want) {
		t.Errorf("version output does not name the release %q:\n%s", want, stdout)
	}
	for _, image := range []string{
		"rainergewalt/trailmq-backend:" + want,
		"rainergewalt/trailmq-frontend:" + want,
	} {
		if !strings.Contains(stdout, image) {
			t.Errorf("version output does not name %q:\n%s", image, stdout)
		}
	}
}

func TestVersionFailsCleanlyWithoutAContract(t *testing.T) {
	// An empty directory with no contract above it: the launcher must say so
	// rather than invent a version or crash.
	dir := t.TempDir()
	t.Setenv("TRAILMQ_ROOT", dir)
	t.Setenv("NO_COLOR", "1")

	code, _, stderr := exercise(t, "version")
	if code != exitFailure {
		t.Errorf("exit = %d, want %d", code, exitFailure)
	}
	if !strings.Contains(stderr, "TRAILMQ_ROOT") {
		t.Errorf("the failure does not say what to do about it:\n%s", stderr)
	}
}

func TestUsageErrors(t *testing.T) {
	t.Setenv("NO_COLOR", "1")

	for _, tc := range []struct {
		name string
		args []string
	}{
		{"no arguments", nil},
		{"unknown command", []string{"quickstart-please"}},
		{"unknown option", []string{"open", "--browser=firefox"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			code, _, _ := exercise(t, tc.args...)
			if code != exitUsage {
				t.Errorf("exit = %d, want %d", code, exitUsage)
			}
		})
	}
}

// Help that advertises a command the dispatcher does not know is a broken
// promise on the first screen a user sees.
func TestHelpOnlyOffersCommandsThatDispatch(t *testing.T) {
	t.Setenv("TRAILMQ_RELEASE_CONTRACT", repoFile(t, "release.yaml"))
	t.Setenv("NO_COLOR", "1")

	_, help, _ := exercise(t, "help")

	for _, command := range []string{"version", "doctor", "open"} {
		if !strings.Contains(help, command) {
			t.Errorf("help does not mention %q:\n%s", command, help)
		}
	}

	// 'doctor' is excluded here because it probes the local Docker
	// installation, which is not this test's subject.
	for _, args := range [][]string{{"version"}, {"open", "--print"}, {"help"}} {
		if code, _, stderr := exercise(t, args...); code == exitUsage {
			t.Errorf("%v was rejected as a usage error: %s", args, stderr)
		}
	}
}

// `open --print` must answer without opening anything, which is what makes it
// usable over SSH and in the test suite.
func TestOpenPrintListsEndpoints(t *testing.T) {
	t.Setenv("TRAILMQ_RELEASE_CONTRACT", repoFile(t, "release.yaml"))
	t.Setenv("TRAILMQ_HTTP_PORT", "8080")
	t.Setenv("TRAILMQ_MQTT_TLS_PORT", "8884")
	t.Setenv("NO_COLOR", "1")

	code, stdout, stderr := exercise(t, "open", "--print")
	if code != exitOK {
		t.Fatalf("exit %d, stderr: %s", code, stderr)
	}
	for _, want := range []string{
		"http://localhost:8080/trailmq/",
		"http://localhost:8080/api/v1",
		"localhost:8884",
		"ws://localhost:8080/mqtt",
	} {
		if !strings.Contains(stdout, want) {
			t.Errorf("endpoints do not include %q:\n%s", want, stdout)
		}
	}
	if strings.Contains(stdout, "Opening") {
		t.Error("--print opened a browser")
	}
}

// The point of a Go launcher is that Windows needs Docker Desktop and nothing
// else. A binary that shells out to bash, sh or a .sh script would keep the
// POSIX dependency alive under a different name, so this asserts the
// production code contains no such call. Test files are exempt: the contract
// package deliberately runs the shell reader to prove the two agree.
func TestLauncherDoesNotShellOutToPOSIX(t *testing.T) {
	root := repoFile(t, "")
	forbidden := []string{"bash", "sh", "/bin/sh", "/bin/bash", "zsh"}

	for _, dir := range []string{"cmd", "internal"} {
		err := filepath.WalkDir(filepath.Join(root, dir), func(path string, d fs.DirEntry, err error) error {
			if err != nil || d.IsDir() {
				return err
			}
			if !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
				return nil
			}

			fset := token.NewFileSet()
			file, perr := parser.ParseFile(fset, path, nil, 0)
			if perr != nil {
				return perr
			}

			ast.Inspect(file, func(n ast.Node) bool {
				call, ok := n.(*ast.CallExpr)
				if !ok {
					return true
				}
				sel, ok := call.Fun.(*ast.SelectorExpr)
				if !ok {
					return true
				}
				pkg, ok := sel.X.(*ast.Ident)
				if !ok || pkg.Name != "exec" {
					return true
				}
				if sel.Sel.Name != "Command" && sel.Sel.Name != "CommandContext" && sel.Sel.Name != "LookPath" {
					return true
				}

				for _, arg := range call.Args {
					lit, ok := arg.(*ast.BasicLit)
					if !ok || lit.Kind != token.STRING {
						continue
					}
					value, uerr := strconv.Unquote(lit.Value)
					if uerr != nil {
						continue
					}
					for _, bad := range forbidden {
						if value == bad || strings.HasSuffix(value, ".sh") {
							t.Errorf("%s:%d executes %q — the launcher must not depend on a POSIX shell",
								path, fset.Position(lit.Pos()).Line, value)
						}
					}
				}
				return true
			})
			return nil
		})
		if err != nil {
			t.Fatal(err)
		}
	}
}

func repoFile(t *testing.T, parts ...string) string {
	t.Helper()
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	return filepath.Join(append([]string{root}, parts...)...)
}

func releaseVersion(t *testing.T) string {
	t.Helper()
	b, err := os.ReadFile(repoFile(t, "release.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	for _, line := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(line, "version: "); ok {
			return strings.TrimSpace(v)
		}
	}
	t.Fatal("release.yaml declares no version")
	return ""
}
