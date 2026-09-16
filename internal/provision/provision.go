// Package provision prepares everything a local evaluation needs before the
// stack can start: state directories, demo TLS certificates, a JWT secret and
// evaluation credentials.
//
// Certificates are generated with crypto/x509 rather than by calling openssl.
// That is not a stylistic preference — Windows has no openssl, and the shell
// launcher's certificate step simply fails there. Generating them in-process
// removes the last tool a Windows evaluator would have had to install beyond
// Docker Desktop.
//
// Everything here is idempotent. Re-running a setup must never overwrite a
// certificate an evaluator is already trusting, or rotate a password they have
// pasted into a client.
package provision

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/pem"
	"fmt"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/layout"
)

// EvaluationUsers are the identities a first run creates. They match the
// recipe's config.yaml; changing one without the other leaves a user that
// cannot sign in.
var EvaluationUsers = []string{"testadmin", "testuser"}

// certValidity matches the shell launcher's demo certificates. These are
// local, self-signed and explicitly not production material, so a year is
// generous rather than short.
const certValidity = 365 * 24 * time.Hour

// Result records what a preparation run actually changed, so the caller can
// report the first run differently from the fifth.
type Result struct {
	CreatedDirs        bool
	CreatedCerts       bool
	CreatedJWTSecret   bool
	CreatedCredentials []string
	// WeakPasswords names credential files that predate the backend's password
	// policy. Those make the container restart in a loop, which is impossible
	// to diagnose from the outside.
	WeakPasswords []string
}

func (r Result) ChangedAnything() bool {
	return r.CreatedDirs || r.CreatedCerts || r.CreatedJWTSecret || len(r.CreatedCredentials) > 0
}

// Prepare brings a recipe to a startable state.
func Prepare(r layout.Recipe) (Result, error) {
	var result Result

	for _, dir := range r.StateDirs() {
		if _, err := os.Stat(dir); os.IsNotExist(err) {
			result.CreatedDirs = true
		}
	}
	if err := r.EnsureStateDirs(); err != nil {
		return result, err
	}

	if _, err := os.Stat(r.ConfigFile()); err != nil {
		return result, fmt.Errorf("the recipe is incomplete: %s is missing", r.ConfigFile())
	}

	created, err := ensureCertificates(r.CertsDir())
	if err != nil {
		return result, err
	}
	result.CreatedCerts = created

	created, err = ensureJWTSecret(filepath.Join(r.SecretsDir(), "jwtsecret.txt"))
	if err != nil {
		return result, err
	}
	result.CreatedJWTSecret = created

	for _, user := range EvaluationUsers {
		path := filepath.Join(r.SecretsDir(), user+".pwd")
		created, err := ensurePassword(path)
		if err != nil {
			return result, err
		}
		if created {
			result.CreatedCredentials = append(result.CreatedCredentials, user)
			continue
		}
		if weak, _ := passwordIsWeak(path); weak {
			result.WeakPasswords = append(result.WeakPasswords, user)
		}
	}

	return result, nil
}

// Credentials reads the generated evaluation logins.
func Credentials(r layout.Recipe) map[string]string {
	out := map[string]string{}
	for _, user := range EvaluationUsers {
		b, err := os.ReadFile(filepath.Join(r.SecretsDir(), user+".pwd"))
		if err != nil {
			continue
		}
		if v := strings.TrimSpace(string(b)); v != "" {
			out[user] = v
		}
	}
	return out
}

// CertificatesPresent reports whether the three files the backend needs exist.
func CertificatesPresent(dir string) bool {
	for _, name := range []string{"ca_cert.pem", "server_cert.pem", "server_key.pem"} {
		if _, err := os.Stat(filepath.Join(dir, name)); err != nil {
			return false
		}
	}
	return true
}

func ensureCertificates(dir string) (bool, error) {
	if CertificatesPresent(dir) {
		return false, nil
	}

	caKey, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return false, fmt.Errorf("could not generate the demo CA key: %w", err)
	}

	serial, err := serialNumber()
	if err != nil {
		return false, err
	}
	now := time.Now()
	caTemplate := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:         "TrailMQ Local Demo CA",
			Organization:       []string{"TrailMQ Demo"},
			OrganizationalUnit: []string{"Local Evaluation"},
		},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.Add(certValidity),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign | x509.KeyUsageDigitalSignature,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            0,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		return false, fmt.Errorf("could not create the demo CA certificate: %w", err)
	}
	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		return false, err
	}

	serverKey, err := rsa.GenerateKey(rand.Reader, 4096)
	if err != nil {
		return false, fmt.Errorf("could not generate the server key: %w", err)
	}

	serial, err = serialNumber()
	if err != nil {
		return false, err
	}
	serverTemplate := &x509.Certificate{
		SerialNumber: serial,
		Subject: pkix.Name{
			CommonName:         "localhost",
			Organization:       []string{"TrailMQ Demo"},
			OrganizationalUnit: []string{"Local Evaluation"},
		},
		NotBefore: now.Add(-time.Hour),
		NotAfter:  now.Add(certValidity),
		KeyUsage:  x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage: []x509.ExtKeyUsage{
			x509.ExtKeyUsageServerAuth,
			x509.ExtKeyUsageClientAuth,
		},
		// The names a client can reach this broker under: from the host, and
		// from inside the Compose network under each service and container
		// name. A certificate missing one of these produces a TLS error that
		// looks like a TrailMQ fault and is not one.
		DNSNames: []string{
			"localhost",
			"backend",
			"nginx",
			"trailmq-backend",
			"trailmq-reverse-proxy",
		},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1"), net.ParseIP("::1")},
		BasicConstraintsValid: true,
	}
	serverDER, err := x509.CreateCertificate(rand.Reader, serverTemplate, caCert, &serverKey.PublicKey, caKey)
	if err != nil {
		return false, fmt.Errorf("could not sign the server certificate: %w", err)
	}

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}

	// Written last and together: a half-written certificate set is worse than
	// none, because the stack starts and fails somewhere less obvious.
	files := []struct {
		name string
		mode os.FileMode
		data []byte
	}{
		{"ca_cert.pem", 0o644, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})},
		{"server_cert.pem", 0o644, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: serverDER})},
		{"server_key.pem", 0o600, pem.EncodeToMemory(&pem.Block{
			Type:  "RSA PRIVATE KEY",
			Bytes: x509.MarshalPKCS1PrivateKey(serverKey),
		})},
	}
	for _, f := range files {
		if err := writeFile(filepath.Join(dir, f.name), f.data, f.mode); err != nil {
			return false, err
		}
	}
	return true, nil
}

func ensureJWTSecret(path string) (bool, error) {
	if st, err := os.Stat(path); err == nil && st.Size() > 0 {
		return false, nil
	}
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return false, fmt.Errorf("could not generate a JWT secret: %w", err)
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	return true, writeFile(path, []byte(hex.EncodeToString(b)), 0o600)
}

// passwordAlphabet excludes characters that are easy to misread when a
// password is copied off a terminal by eye.
const passwordAlphabet = "abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"

func ensurePassword(path string) (bool, error) {
	if st, err := os.Stat(path); err == nil && st.Size() > 0 {
		return false, nil
	}

	password, err := generatePassword()
	if err != nil {
		return false, err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return false, err
	}
	return true, writeFile(path, []byte(password), 0o600)
}

// generatePassword composes a password that always satisfies the backend's
// policy: upper case, lower case, a digit and a special character. Sampling
// randomly and hoping every class appears would occasionally produce a
// password the backend rejects, and the symptom of that is a container
// restarting in a loop rather than an error anyone can read.
//
// '-' and '_' are the special characters because they survive being pasted
// into a shell, YAML, JSON and a URL without quoting.
func generatePassword() (string, error) {
	first, err := randomString(6)
	if err != nil {
		return "", err
	}
	second, err := randomString(6)
	if err != nil {
		return "", err
	}
	n, err := rand.Int(rand.Reader, big.NewInt(100))
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Ev%02d-%s_%s", n.Int64(), first, second), nil
}

func randomString(n int) (string, error) {
	var b strings.Builder
	max := big.NewInt(int64(len(passwordAlphabet)))
	for i := 0; i < n; i++ {
		idx, err := rand.Int(rand.Reader, max)
		if err != nil {
			return "", err
		}
		b.WriteByte(passwordAlphabet[idx.Int64()])
	}
	return b.String(), nil
}

// passwordIsWeak reports a credential written by an older launcher, before the
// backend enforced a password policy. Those are purely alphanumeric, and the
// backend refuses to start with one.
func passwordIsWeak(path string) (bool, error) {
	b, err := os.ReadFile(path)
	if err != nil {
		return false, err
	}
	value := strings.TrimSpace(string(b))
	if value == "" {
		return false, nil
	}
	for _, r := range value {
		isAlnum := (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9')
		if !isAlnum {
			return false, nil
		}
	}
	return true, nil
}

func serialNumber() (*big.Int, error) {
	limit := new(big.Int).Lsh(big.NewInt(1), 128)
	serial, err := rand.Int(rand.Reader, limit)
	if err != nil {
		return nil, fmt.Errorf("could not generate a certificate serial number: %w", err)
	}
	return serial, nil
}

func writeFile(path string, data []byte, mode os.FileMode) error {
	if err := os.WriteFile(path, data, mode); err != nil {
		return fmt.Errorf("could not write %s: %w", path, err)
	}
	// WriteFile only applies the mode when it creates the file, and on a
	// rerun the key must not be left world-readable from an earlier version.
	return os.Chmod(path, mode)
}
