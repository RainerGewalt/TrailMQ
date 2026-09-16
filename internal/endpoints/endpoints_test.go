package endpoints

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDefaultsOmitThePortWhenItIsTheDefault(t *testing.T) {
	clearEnv(t)
	e := Load(t.TempDir())

	// Port 80 in a URL is noise, and an evaluator copying the address into a
	// browser should get the same thing the documentation shows.
	if got, want := e.WebUI(), "http://localhost/trailmq/"; got != want {
		t.Errorf("WebUI() = %q, want %q", got, want)
	}
	if got, want := e.MQTTOverWebSocket(), "ws://localhost/mqtt"; got != want {
		t.Errorf("MQTTOverWebSocket() = %q, want %q", got, want)
	}
	if got, want := e.MQTTOverTLS(), "localhost:8883"; got != want {
		t.Errorf("MQTTOverTLS() = %q, want %q", got, want)
	}
}

func TestEnvironmentOverridesTheDefaults(t *testing.T) {
	clearEnv(t)
	t.Setenv("TRAILMQ_HTTP_PORT", "8080")
	t.Setenv("TRAILMQ_MQTT_TLS_PORT", "8884")

	e := Load(t.TempDir())
	if got, want := e.WebUI(), "http://localhost:8080/trailmq/"; got != want {
		t.Errorf("WebUI() = %q, want %q", got, want)
	}
	if got, want := e.MQTTOverTLS(), "localhost:8884"; got != want {
		t.Errorf("MQTTOverTLS() = %q, want %q", got, want)
	}
}

func TestDotEnvIsReadButNeverBeatsTheEnvironment(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, ".env"), ""+
		"# a comment\n"+
		"TRAILMQ_HTTP_PORT=9090\n"+
		"export TRAILMQ_MQTT_TLS_PORT=\"9883\"\n"+
		"UNRELATED=ignored\n")

	clearEnv(t)
	e := Load(dir)
	if got, want := e.HTTPPort, "9090"; got != want {
		t.Errorf("HTTPPort from .env = %q, want %q", got, want)
	}
	if got, want := e.MQTTTLSPort, "9883"; got != want {
		t.Errorf("MQTTTLSPort from .env = %q, want %q", got, want)
	}

	// An override typed on the command line must not be silently replaced by
	// a file the user forgot was there.
	t.Setenv("TRAILMQ_HTTP_PORT", "7070")
	if got, want := Load(dir).HTTPPort, "7070"; got != want {
		t.Errorf("environment lost to .env: got %q, want %q", got, want)
	}
}

func TestMissingDotEnvIsNotAnError(t *testing.T) {
	clearEnv(t)
	if got, want := Load(t.TempDir()).HTTPPort, DefaultHTTPPort; got != want {
		t.Errorf("HTTPPort = %q, want the default %q", got, want)
	}
}

func TestInUseDetectsAListener(t *testing.T) {
	clearEnv(t)
	// A port nothing is listening on must not be reported as busy, or doctor
	// would tell every user to change their configuration.
	if InUse("1") {
		t.Error("InUse reported a listener on a port that should be free")
	}
}

func clearEnv(t *testing.T) {
	t.Helper()
	for _, k := range []string{"TRAILMQ_HTTP_PORT", "TRAILMQ_MQTT_TLS_PORT"} {
		if _, ok := os.LookupEnv(k); ok {
			t.Setenv(k, "")
			os.Unsetenv(k)
		}
	}
}

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}
