// Package endpoints derives the local addresses an evaluation exposes.
//
// Ports are configurable, so the launcher must never print a hardcoded URL: a
// user who moved the stack off port 80 because IIS or another service owns it
// would be told to open an address that belongs to something else.
package endpoints

import (
	"bufio"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"strings"
	"time"
)

const (
	DefaultHTTPPort    = "80"
	DefaultMQTTTLSPort = "8883"
)

type Endpoints struct {
	HTTPPort    string
	MQTTTLSPort string
}

// Load resolves the ports from the environment, then from a .env file in root
// if one is present. Explicit environment variables win, matching the shell
// launcher: an override typed on the command line should not be quietly
// replaced by a file.
func Load(root string) Endpoints {
	e := Endpoints{
		HTTPPort:    DefaultHTTPPort,
		MQTTTLSPort: DefaultMQTTTLSPort,
	}

	fromFile := readEnvFile(filepath.Join(root, ".env"))
	for _, spec := range []struct {
		key    string
		target *string
	}{
		{"TRAILMQ_HTTP_PORT", &e.HTTPPort},
		{"TRAILMQ_MQTT_TLS_PORT", &e.MQTTTLSPort},
	} {
		if v := os.Getenv(spec.key); v != "" {
			*spec.target = v
		} else if v, ok := fromFile[spec.key]; ok && v != "" {
			*spec.target = v
		}
	}
	return e
}

// readEnvFile reads the TRAILMQ_* assignments from a .env file. It is
// deliberately not a general dotenv implementation: the launcher only needs
// its own keys, and parsing everything would mean deciding what to do with
// shell constructs that have no meaning here.
func readEnvFile(path string) map[string]string {
	out := map[string]string{}
	f, err := os.Open(path)
	if err != nil {
		return out
	}
	defer f.Close()

	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := strings.TrimSpace(sc.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		key, value, found := strings.Cut(line, "=")
		if !found {
			continue
		}
		key = strings.TrimSpace(key)
		if !strings.HasPrefix(key, "TRAILMQ_") {
			continue
		}
		value = strings.TrimSpace(value)
		value = strings.Trim(value, `"'`)
		out[key] = value
	}
	return out
}

// EnvOverrides returns the TRAILMQ_* assignments a child process needs, as
// KEY=VALUE.
//
// Compose reads a .env file next to the Compose file, but TrailMQ's lives at
// the installation root, one level up. Without this, a user who set
// TRAILMQ_HTTP_PORT in .env would get a launcher printing one port and a stack
// listening on another.
func EnvOverrides(root string) []string {
	fromFile := readEnvFile(filepath.Join(root, ".env"))

	var out []string
	for _, key := range []string{"TRAILMQ_HTTP_PORT", "TRAILMQ_MQTT_TLS_PORT",
		"TRAILMQ_BACKEND_IMAGE", "TRAILMQ_FRONTEND_IMAGE", "TRAILMQ_NGINX_IMAGE"} {
		if v := os.Getenv(key); v != "" {
			out = append(out, key+"="+v)
			continue
		}
		if v, ok := fromFile[key]; ok && v != "" {
			out = append(out, key+"="+v)
		}
	}
	return out
}

func (e Endpoints) httpBase() string {
	if e.HTTPPort == DefaultHTTPPort {
		return "http://localhost"
	}
	return "http://localhost:" + e.HTTPPort
}

// WebUI is the address `trailmq open` opens.
func (e Endpoints) WebUI() string { return e.httpBase() + "/trailmq/" }

func (e Endpoints) RestAPI() string { return e.httpBase() + "/api/v1" }

func (e Endpoints) MQTTOverTLS() string { return "localhost:" + e.MQTTTLSPort }

func (e Endpoints) MQTTOverWebSocket() string {
	if e.HTTPPort == DefaultHTTPPort {
		return "ws://localhost/mqtt"
	}
	return "ws://localhost:" + e.HTTPPort + "/mqtt"
}

// InUse reports whether something is already listening on a port.
//
// It connects rather than binds. Binding would be the more direct test, but
// binding a privileged port fails for an unprivileged user even when the port
// is free, which would report a conflict that does not exist.
func InUse(port string) bool {
	conn, err := net.DialTimeout("tcp", net.JoinHostPort("127.0.0.1", port), 300*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func (e Endpoints) String() string {
	return fmt.Sprintf("http=%s mqtt-tls=%s", e.HTTPPort, e.MQTTTLSPort)
}
