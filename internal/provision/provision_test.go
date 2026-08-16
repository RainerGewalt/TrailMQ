package provision

import (
	"crypto/x509"
	"encoding/pem"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"github.com/RainerGewalt/TrailMQ/internal/layout"
)

func TestPrepareProducesAStartableEvaluation(t *testing.T) {
	r := newRecipe(t)

	result, err := Prepare(r)
	if err != nil {
		t.Fatalf("Prepare: %v", err)
	}
	if !result.CreatedCerts || !result.CreatedJWTSecret {
		t.Errorf("a first run did not report creating certificates and a JWT secret: %+v", result)
	}
	if len(result.CreatedCredentials) != len(EvaluationUsers) {
		t.Errorf("created %d credentials, want %d", len(result.CreatedCredentials), len(EvaluationUsers))
	}
	if !CertificatesPresent(r.CertsDir()) {
		t.Fatal("certificates are not present after Prepare")
	}
}

// Re-running a setup must never rotate a certificate an evaluator has already
// trusted or a password they have pasted into a client.
func TestPrepareIsIdempotent(t *testing.T) {
	r := newRecipe(t)
	if _, err := Prepare(r); err != nil {
		t.Fatal(err)
	}

	before := read(t, filepath.Join(r.CertsDir(), "server_cert.pem"))
	beforePassword := Credentials(r)["testadmin"]

	result, err := Prepare(r)
	if err != nil {
		t.Fatal(err)
	}
	if result.ChangedAnything() {
		t.Errorf("a second run changed something: %+v", result)
	}
	if after := read(t, filepath.Join(r.CertsDir(), "server_cert.pem")); after != before {
		t.Error("the server certificate was regenerated")
	}
	if after := Credentials(r)["testadmin"]; after != beforePassword {
		t.Error("the evaluation password was rotated")
	}
}

// The certificate has to be usable by clients reaching the broker from the
// host and from inside the Compose network. A missing name produces a TLS
// error that reads like a TrailMQ fault.
func TestServerCertificateCoversEveryNameTheStackUses(t *testing.T) {
	r := newRecipe(t)
	if _, err := Prepare(r); err != nil {
		t.Fatal(err)
	}

	cert := parseCert(t, filepath.Join(r.CertsDir(), "server_cert.pem"))
	for _, name := range []string{
		"localhost", "backend", "nginx", "trailmq-backend", "trailmq-reverse-proxy",
	} {
		if err := cert.VerifyHostname(name); err != nil {
			t.Errorf("the server certificate does not cover %q: %v", name, err)
		}
	}
	for _, ip := range []string{"127.0.0.1", "::1"} {
		found := false
		for _, got := range cert.IPAddresses {
			if got.Equal(net.ParseIP(ip)) {
				found = true
			}
		}
		if !found {
			t.Errorf("the server certificate does not cover %s", ip)
		}
	}
}

func TestServerCertificateChainsToTheGeneratedCA(t *testing.T) {
	r := newRecipe(t)
	if _, err := Prepare(r); err != nil {
		t.Fatal(err)
	}

	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM([]byte(read(t, filepath.Join(r.CertsDir(), "ca_cert.pem")))) {
		t.Fatal("ca_cert.pem is not a usable PEM certificate")
	}

	cert := parseCert(t, filepath.Join(r.CertsDir(), "server_cert.pem"))
	if _, err := cert.Verify(x509.VerifyOptions{
		Roots:     pool,
		DNSName:   "localhost",
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	}); err != nil {
		t.Errorf("the server certificate does not verify against the generated CA: %v", err)
	}
}

func TestPrivateMaterialIsNotWorldReadable(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("POSIX file modes do not apply on Windows")
	}

	r := newRecipe(t)
	if _, err := Prepare(r); err != nil {
		t.Fatal(err)
	}

	for _, path := range []string{
		filepath.Join(r.CertsDir(), "server_key.pem"),
		filepath.Join(r.SecretsDir(), "jwtsecret.txt"),
		filepath.Join(r.SecretsDir(), "testadmin.pwd"),
	} {
		st, err := os.Stat(path)
		if err != nil {
			t.Fatal(err)
		}
		if mode := st.Mode().Perm(); mode&0o077 != 0 {
			t.Errorf("%s has mode %o, want no group or world access", path, mode)
		}
	}
}

// The backend enforces a password policy and restarts in a loop when it is not
// met, which is undiagnosable from the outside. Generation must satisfy it
// every time, not usually.
func TestGeneratedPasswordsAlwaysSatisfyThePolicy(t *testing.T) {
	for i := 0; i < 200; i++ {
		password, err := generatePassword()
		if err != nil {
			t.Fatal(err)
		}
		var upper, lower, digit, special bool
		for _, r := range password {
			switch {
			case r >= 'A' && r <= 'Z':
				upper = true
			case r >= 'a' && r <= 'z':
				lower = true
			case r >= '0' && r <= '9':
				digit = true
			default:
				special = true
			}
		}
		if !upper || !lower || !digit || !special {
			t.Fatalf("password %q does not satisfy the policy (upper=%v lower=%v digit=%v special=%v)",
				password, upper, lower, digit, special)
		}
		if len(password) < 12 {
			t.Fatalf("password %q is shorter than 12 characters", password)
		}
	}
}

func TestWeakLegacyPasswordsAreReported(t *testing.T) {
	r := newRecipe(t)
	if err := r.EnsureStateDirs(); err != nil {
		t.Fatal(err)
	}

	// What an older launcher wrote: alphanumeric only.
	legacy := filepath.Join(r.SecretsDir(), "testadmin.pwd")
	if err := os.WriteFile(legacy, []byte("Evaluation123"), 0o600); err != nil {
		t.Fatal(err)
	}

	result, err := Prepare(r)
	if err != nil {
		t.Fatal(err)
	}
	if len(result.WeakPasswords) != 1 || result.WeakPasswords[0] != "testadmin" {
		t.Errorf("WeakPasswords = %v, want [testadmin]", result.WeakPasswords)
	}
	// A weak password must be reported, never silently replaced — the user may
	// already be using it.
	if got := Credentials(r)["testadmin"]; got != "Evaluation123" {
		t.Errorf("the existing password was replaced: got %q", got)
	}
}

func TestPrepareRefusesAnIncompleteRecipe(t *testing.T) {
	l := layout.Resolve(filepath.Join(t.TempDir(), "release.yaml"))
	r := l.Recipe("secure-mqtt-core")
	if err := os.MkdirAll(r.Assets, 0o755); err != nil {
		t.Fatal(err)
	}
	// No config.yaml: the stack would start and fail somewhere less obvious.
	if _, err := Prepare(r); err == nil {
		t.Error("Prepare accepted a recipe with no config.yaml")
	} else if !strings.Contains(err.Error(), "config.yaml") {
		t.Errorf("the error does not name the missing file: %v", err)
	}
}

func newRecipe(t *testing.T) layout.Recipe {
	t.Helper()
	l := layout.Resolve(filepath.Join(t.TempDir(), "release.yaml"))
	r := l.Recipe("secure-mqtt-core")
	if err := os.MkdirAll(r.Assets, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(r.ConfigFile(), []byte("rest_port: 8443\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return r
}

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func parseCert(t *testing.T, path string) *x509.Certificate {
	t.Helper()
	block, _ := pem.Decode([]byte(read(t, path)))
	if block == nil {
		t.Fatalf("%s is not PEM", path)
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatal(err)
	}
	return cert
}
