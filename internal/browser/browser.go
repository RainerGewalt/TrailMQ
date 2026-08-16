// Package browser opens a URL in the user's browser.
//
// `trailmq open` means open. Printing the URL and calling that "opening" is
// what the shell launcher did, and it left the most common case — a Windows
// user who just wants to see the product — doing clipboard work the tool
// should have done.
//
// Opening still fails legitimately: a headless server, a container, an SSH
// session. Those return an error so the caller can print the URL instead. That
// is a fallback, not the normal path.
package browser

import (
	"context"
	"errors"
	"os"
	"os/exec"
	"runtime"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/platform"
)

// ErrNoBrowser reports that this machine has nothing to open a URL with.
var ErrNoBrowser = errors.New("no browser could be opened on this machine")

// openTimeout bounds the launch. The opener is expected to return immediately
// after handing the URL to the desktop; one that blocks has failed in a way
// the user should not have to wait out.
const openTimeout = 10 * time.Second

// Open hands url to the desktop's default browser.
func Open(url string) error { return open(platform.Detect(), url) }

func open(p platform.Info, url string) error {
	for _, c := range candidates(p, url) {
		ctx, cancel := context.WithTimeout(context.Background(), openTimeout)
		cmd := exec.CommandContext(ctx, c.name, c.args...)
		// Openers routinely write desktop-portal noise across the summary the
		// user is meant to be reading.
		cmd.Stdout = nil
		cmd.Stderr = nil
		err := cmd.Start()
		if err != nil {
			cancel()
			continue
		}
		// The opener is a launcher, not a browser: it exits as soon as the
		// desktop takes the URL. Reaping it in the background keeps this from
		// blocking, and keeps a zombie off the process table.
		go func() {
			defer cancel()
			_ = cmd.Wait()
		}()
		return nil
	}
	return ErrNoBrowser
}

type candidate struct {
	name string
	args []string
}

func candidates(p platform.Info, url string) []candidate {
	// WSL first: it has a Linux userland, but the browser the user is looking
	// at runs on Windows. xdg-open there either does nothing or opens a Linux
	// browser on a display nobody is watching.
	if p.WSL {
		return []candidate{
			{"wslview", []string{url}},
			{"powershell.exe", []string{"-NoProfile", "-Command", "Start-Process", "'" + url + "'"}},
			{"cmd.exe", []string{"/c", "start", "", url}},
		}
	}

	switch p.OS {
	case "windows":
		// rundll32 is used in preference to `cmd /c start` because start
		// treats its first quoted argument as a window title and mangles URLs
		// containing an ampersand.
		return []candidate{
			{"rundll32", []string{"url.dll,FileProtocolHandler", url}},
		}
	case "darwin":
		return []candidate{{"open", []string{url}}}
	default:
		// A Linux host with no graphical session has nothing to open. Testing
		// for a session first avoids an opener error that reads like a TrailMQ
		// failure but is not one.
		if os.Getenv("DISPLAY") == "" && os.Getenv("WAYLAND_DISPLAY") == "" {
			return nil
		}
		return []candidate{
			{"xdg-open", []string{url}},
			{"gio", []string{"open", url}},
		}
	}
}

// Available reports whether opening a browser is plausible here, so a caller
// can phrase its output before trying.
func Available() bool {
	p := platform.Detect()
	if runtime.GOOS == "windows" {
		return true
	}
	for _, c := range candidates(p, "about:blank") {
		if _, err := exec.LookPath(c.name); err == nil {
			return true
		}
	}
	return false
}
