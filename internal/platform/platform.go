// Package platform identifies the machine the launcher is running on.
//
// It exists so that the rest of the launcher never branches on runtime.GOOS
// directly. What callers actually need is not "is this windows" but "what is
// the Docker product called here" and "does opening a browser mean handing the
// URL to a different operating system" — questions this package answers once.
package platform

import (
	"os"
	"runtime"
	"strings"
)

type Info struct {
	OS   string // GOOS
	Arch string // GOARCH
	// WSL reports a Linux userland whose user is looking at a Windows desktop.
	// It is neither plain Linux nor Windows for anything user-facing.
	WSL bool
}

func Detect() Info {
	return Info{
		OS:   runtime.GOOS,
		Arch: runtime.GOARCH,
		WSL:  detectWSL(),
	}
}

func detectWSL() bool {
	if runtime.GOOS != "linux" {
		return false
	}
	b, err := os.ReadFile("/proc/version")
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToLower(string(b)), "microsoft")
}

func (i Info) IsWindows() bool { return i.OS == "windows" }

// Name is what a person calls this platform, not what the toolchain calls it.
func (i Info) Name() string {
	switch {
	case i.WSL:
		return "Windows (WSL)"
	case i.OS == "windows":
		return "Windows"
	case i.OS == "darwin":
		return "macOS"
	case i.OS == "linux":
		return "Linux"
	default:
		return i.OS
	}
}

// DockerProduct is the name of the thing the user has to start. Telling a
// Windows user to "start the Docker daemon" sends them looking for something
// that does not appear under that name anywhere on their machine.
func (i Info) DockerProduct() string {
	switch i.OS {
	case "windows", "darwin":
		return "Docker Desktop"
	default:
		if i.WSL {
			return "Docker Desktop"
		}
		return "the Docker engine"
	}
}

// RuntimeArch is the container architecture this platform pulls by default.
// TrailMQ runtime images are published for linux/amd64; an Apple Silicon or
// ARM Linux host therefore runs them under emulation, which is worth saying
// out loud rather than leaving to be discovered mid-evaluation.
func (i Info) RuntimeArch() string {
	switch i.Arch {
	case "arm64":
		return "linux/arm64"
	case "amd64":
		return "linux/amd64"
	default:
		return "linux/" + i.Arch
	}
}

// String renders the platform for diagnostics.
func (i Info) String() string { return i.Name() + " " + i.Arch }
