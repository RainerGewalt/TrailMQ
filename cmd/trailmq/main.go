// Command trailmq is the TrailMQ launcher.
//
// It is a single static binary with no dependencies outside the standard
// library, cross-compiled for Windows, Linux and macOS from one source. That
// matters for the platform TrailMQ is least reachable on today: a Windows
// evaluator should need Docker Desktop and nothing else — no Git, no Bash, no
// WSL — and a launcher that shells out to a POSIX script would keep that
// dependency alive under a different name.
//
// This binary currently implements the commands that establish the foundation:
// version, doctor and open. Stack orchestration still lives in the shell
// launcher alongside it, and both read the same release contract.
//
// Exit codes are part of the interface, so a script wrapping this tool can
// tell the cases apart:
//
//	0  success
//	1  the command failed
//	2  the command was used incorrectly
//	3  the environment is not ready (doctor found a blocking problem)
package main

import (
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/RainerGewalt/TrailMQ/internal/browser"
	"github.com/RainerGewalt/TrailMQ/internal/contract"
	"github.com/RainerGewalt/TrailMQ/internal/diagnostics"
	"github.com/RainerGewalt/TrailMQ/internal/endpoints"
	"github.com/RainerGewalt/TrailMQ/internal/output"
)

const (
	exitOK          = 0
	exitFailure     = 1
	exitUsage       = 2
	exitEnvironment = 3
)

func main() {
	os.Exit(run(os.Args[1:], os.Stdout, os.Stderr))
}

// run is separated from main so the commands can be exercised with captured
// output instead of by shelling out to a built binary.
func run(args []string, stdout, stderr io.Writer) int {
	out := output.New(stdout)
	errOut := output.New(stderr)

	if len(args) == 0 {
		usage(out)
		return exitUsage
	}

	command, rest := args[0], args[1:]

	switch command {
	case "version", "--version", "-v":
		return cmdVersion(out, errOut)
	case "doctor":
		return cmdDoctor(out)
	case "open":
		return cmdOpen(out, errOut, rest)
	case "status":
		return cmdStatus(out, errOut)
	case "quickstart":
		return cmdQuickstart(out, errOut)
	case "start":
		return cmdStart(out, errOut)
	case "stop":
		return cmdStop(out, errOut)
	case "verify":
		return cmdVerify(out, errOut, rest)
	case "credentials", "creds":
		return cmdCredentials(out, errOut)
	case "help", "--help", "-h":
		usage(out)
		return exitOK
	default:
		errOut.Fail("Unknown command: %s", command)
		errOut.Blank()
		usage(errOut)
		return exitUsage
	}
}

func usage(p *output.Printer) {
	p.Title("TrailMQ — an MQTT broker that decides, enforces and records")
	p.Blank()
	p.Title("Usage")
	p.Println("  trailmq <command>")
	p.Blank()
	p.Title("Start here")
	p.Field("quickstart", "Prepare and start a local evaluation")
	p.Field("open", "Open TrailMQ in your browser")
	p.Blank()
	p.Title("Operate")
	p.Field("status", "Show what is running")
	p.Field("start", "Start a prepared evaluation")
	p.Field("stop", "Stop the stack and keep the data")
	p.Blank()
	p.Title("Prove and inspect")
	p.Field("verify", "Run the decision proof")
	p.Field("credentials", "Show the generated evaluation logins")
	p.Blank()
	p.Title("Diagnose")
	p.Field("doctor", "Check whether this machine can run TrailMQ")
	p.Field("version", "Show the release this launcher belongs to")
	p.Blank()
	p.Dim("Client onboarding (connect) and log tailing are still served by the")
	p.Dim("./trailmq shell launcher in the evaluation package.")
}

// loadContract resolves the release contract and the directory holding it.
// The directory is the TrailMQ root: the evaluation package's own folder,
// whether that is a clone, an extracted bundle or an installation.
func loadContract() (*contract.Contract, string, error) {
	c, err := contract.LoadFound()
	if err != nil {
		return nil, "", err
	}
	return c, filepath.Dir(c.Path), nil
}

func cmdVersion(out, errOut *output.Printer) int {
	c, _, err := loadContract()
	if err != nil {
		errOut.Fail("Could not determine which TrailMQ release this launcher belongs to.")
		errOut.Detail(err.Error())
		errOut.Blank()
		errOut.Detail("Run trailmq from the TrailMQ directory, or set TRAILMQ_ROOT to it.")
		return exitFailure
	}

	version, err := c.Version()
	if err != nil {
		errOut.Fail("The release contract declares no version.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	backend, _ := c.Get("runtime.backend")
	frontend, _ := c.Get("runtime.frontend")

	out.Title("TrailMQ " + version)
	out.Field("Backend image", "rainergewalt/trailmq-backend:"+backend)
	out.Field("Frontend image", "rainergewalt/trailmq-frontend:"+frontend)
	out.Field("Contract", c.Path)
	return exitOK
}

func cmdDoctor(out *output.Printer) int {
	// A missing contract is itself a finding, so the report is produced either
	// way rather than the command refusing to run.
	c, root, err := loadContract()
	if err != nil {
		c, root = nil, ""
	}

	report := diagnostics.Run(context.Background(), root, c)

	out.Title("TrailMQ environment check")
	out.Blank()

	for _, check := range report.Checks {
		label := fmt.Sprintf("%-16s %s", check.Name, check.Detail)
		switch check.Status {
		case diagnostics.Pass:
			out.OK("%s", label)
		case diagnostics.Warn:
			out.Warn("%s", label)
		case diagnostics.Fail:
			out.Fail("%s", label)
		}
		if check.Remedy != "" {
			out.Detail(check.Remedy)
		}
	}

	out.Blank()
	if report.Blocked() {
		out.Fail("This machine cannot run TrailMQ yet.")
		out.Dim("Fix the items above and run 'trailmq doctor' again.")
		return exitEnvironment
	}
	out.OK("This machine can run TrailMQ.")
	return exitOK
}

func cmdOpen(out, errOut *output.Printer, args []string) int {
	printOnly := false
	for _, a := range args {
		switch a {
		case "--print":
			printOnly = true
		default:
			errOut.Fail("Unknown option for 'open': %s", a)
			errOut.Detail("Supported: --print, which lists the endpoints without opening a browser.")
			return exitUsage
		}
	}

	_, root, err := loadContract()
	if err != nil {
		// Endpoints do not actually need the contract, so a missing one is
		// reported without refusing to answer.
		root = "."
	}

	e := endpoints.Load(root)

	out.Title("TrailMQ endpoints")
	out.Field("Web UI", out.Link(e.WebUI()))
	out.Field("REST API", out.Link(e.RestAPI()))
	out.Field("MQTT TLS", out.Link(e.MQTTOverTLS()))
	out.Field("MQTT WebSocket", out.Link(e.MQTTOverWebSocket()))

	if printOnly {
		return exitOK
	}

	out.Blank()
	if err := browser.Open(e.WebUI()); err != nil {
		// Not a failure of the command: on a server or over SSH there is
		// nothing to open, and the addresses above are the whole answer.
		out.Dim("No browser could be opened here — use the Web UI address above.")
		return exitOK
	}
	out.Step("Opening %s", e.WebUI())
	return exitOK
}
