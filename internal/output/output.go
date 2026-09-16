// Package output renders launcher output consistently.
//
// The launcher talks to people who are not necessarily developers: an
// automation engineer on a Windows workstation, a quality reviewer following a
// walkthrough. Colour is decoration, so it is disabled whenever it would be
// noise — piped output, NO_COLOR, a Windows console that predates ANSI
// support — and the symbols still carry the meaning without it.
package output

import (
	"fmt"
	"io"
	"os"
	"runtime"
	"strings"
)

type Printer struct {
	w     io.Writer
	color bool
}

const (
	reset  = "\033[0m"
	dim    = "\033[2m"
	bold   = "\033[1m"
	red    = "\033[31m"
	green  = "\033[32m"
	yellow = "\033[33m"
	cyan   = "\033[36m"
)

// New returns a printer for w. Colour is used only when w is a terminal and
// the environment has not asked for plain output.
func New(w io.Writer) *Printer {
	return &Printer{w: w, color: shouldColor(w)}
}

func shouldColor(w io.Writer) bool {
	if os.Getenv("NO_COLOR") != "" {
		return false
	}
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	st, err := f.Stat()
	if err != nil || st.Mode()&os.ModeCharDevice == 0 {
		return false
	}
	// Windows terminals only reliably interpret ANSI when a modern console
	// host is in use, which WT_SESSION and TERM together identify well enough.
	// Guessing wrong here prints escape codes at the user, so the default is no.
	if runtime.GOOS == "windows" {
		return os.Getenv("WT_SESSION") != "" || os.Getenv("TERM") != ""
	}
	return true
}

func (p *Printer) paint(code, s string) string {
	if !p.color {
		return s
	}
	return code + s + reset
}

func (p *Printer) Printf(format string, a ...any) {
	fmt.Fprintf(p.w, format, a...)
}

func (p *Printer) Println(a ...any) { fmt.Fprintln(p.w, a...) }

func (p *Printer) Blank() { fmt.Fprintln(p.w) }

func (p *Printer) Title(s string) { fmt.Fprintln(p.w, p.paint(bold, s)) }

func (p *Printer) OK(format string, a ...any) {
	fmt.Fprintf(p.w, "%s %s\n", p.paint(green, "✓"), fmt.Sprintf(format, a...))
}

func (p *Printer) Warn(format string, a ...any) {
	fmt.Fprintf(p.w, "%s %s\n", p.paint(yellow, "!"), fmt.Sprintf(format, a...))
}

func (p *Printer) Fail(format string, a ...any) {
	fmt.Fprintf(p.w, "%s %s\n", p.paint(red, "✗"), fmt.Sprintf(format, a...))
}

func (p *Printer) Step(format string, a ...any) {
	fmt.Fprintf(p.w, "%s %s\n", p.paint(cyan, "→"), fmt.Sprintf(format, a...))
}

func (p *Printer) Dim(format string, a ...any) {
	fmt.Fprintln(p.w, p.paint(dim, fmt.Sprintf(format, a...)))
}

func (p *Printer) Link(s string) string { return p.paint(cyan, s) }

// Detail prints an indented explanation under a result. Remedies are written
// as sentences rather than error strings, so each line is indented as a block
// instead of only the first.
func (p *Printer) Detail(s string) {
	for _, line := range strings.Split(strings.TrimRight(s, "\n"), "\n") {
		fmt.Fprintf(p.w, "    %s\n", p.paint(dim, line))
	}
}

// Field prints an aligned label and value, for the small key/value blocks the
// launcher uses in place of tables.
func (p *Printer) Field(label, value string) {
	fmt.Fprintf(p.w, "  %-16s %s\n", label, value)
}
