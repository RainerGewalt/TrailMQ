// Package contract reads release.yaml, the TrailMQ release contract.
//
// The contract states which component versions belong to a release. The
// launcher reads it directly rather than carrying a compiled-in version,
// because a launcher that names a release the recipe does not pull is exactly
// the drift the contract exists to prevent.
//
// This parser accepts the same small YAML subset as scripts/release-contract.sh
// and rejects everything else with a line number. The two readers are kept in
// step by contract_test.go, which asserts the shapes both must accept and the
// shapes both must refuse. A file that one reader understands and the other
// silently misreads would be worse than having no contract at all.
package contract

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// FileName is the contract's name wherever it appears — repository root,
// evaluation bundle, or installed directory.
const FileName = "release.yaml"

// Contract is a parsed release contract.
type Contract struct {
	// Path is where the contract was read from, so diagnostics can say which
	// file they are talking about.
	Path string

	values map[string]string
	order  []string
}

// ErrNotFound reports that no contract could be located.
var ErrNotFound = errors.New("no release.yaml found")

// Get returns the value at a dotted path.
func (c *Contract) Get(path string) (string, bool) {
	v, ok := c.values[path]
	return v, ok
}

// MustGet returns the value at a dotted path, or an error naming the file and
// the missing key — a contract that forgot something is a different failure
// from a contract that could not be read, and callers report them differently.
func (c *Contract) MustGet(path string) (string, error) {
	v, ok := c.values[path]
	if !ok {
		return "", fmt.Errorf("%s: no such key: %s", c.Path, path)
	}
	return v, nil
}

// Keys returns every leaf path in document order.
func (c *Contract) Keys() []string {
	out := make([]string, len(c.order))
	copy(out, c.order)
	return out
}

// Version is the release version the contract declares.
func (c *Contract) Version() (string, error) { return c.MustGet("version") }

// Declared reports whether a track exists in this release. Tracks that do not
// exist yet are declared "null" rather than omitted, so absence and oversight
// stay distinguishable.
func (c *Contract) Declared(path string) (string, bool) {
	v, ok := c.values[path]
	if !ok || v == "null" {
		return "", false
	}
	return v, true
}

// Load parses the contract at path.
func Load(path string) (*Contract, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	return parse(f, path)
}

// Find locates the contract, most explicit source first:
//
//	TRAILMQ_RELEASE_CONTRACT   an exact file, for tests and unusual layouts
//	TRAILMQ_ROOT               an installation root
//	the executable's directory, walking up
//	the working directory, walking up
//
// The executable is consulted before the working directory because a user who
// runs trailmq.exe from their home folder means the installed release, not
// whatever happens to sit in the current directory.
func Find() (string, error) {
	if p := os.Getenv("TRAILMQ_RELEASE_CONTRACT"); p != "" {
		if fileExists(p) {
			return p, nil
		}
		return "", fmt.Errorf("TRAILMQ_RELEASE_CONTRACT is set to %s, which does not exist", p)
	}

	if root := os.Getenv("TRAILMQ_ROOT"); root != "" {
		p := filepath.Join(root, FileName)
		if fileExists(p) {
			return p, nil
		}
		return "", fmt.Errorf("TRAILMQ_ROOT is set to %s, which contains no %s", root, FileName)
	}

	if exe, err := os.Executable(); err == nil {
		if exe, err = filepath.EvalSymlinks(exe); err == nil {
			if p, ok := searchUpward(filepath.Dir(exe)); ok {
				return p, nil
			}
		}
	}

	if cwd, err := os.Getwd(); err == nil {
		if p, ok := searchUpward(cwd); ok {
			return p, nil
		}
	}

	return "", ErrNotFound
}

// LoadFound locates and parses the contract in one step.
func LoadFound() (*Contract, error) {
	path, err := Find()
	if err != nil {
		return nil, err
	}
	return Load(path)
}

// searchUpward walks toward the filesystem root looking for the contract. The
// depth limit keeps a launcher started in an unrelated directory from scanning
// a whole filesystem before admitting it cannot find its own release.
func searchUpward(dir string) (string, bool) {
	const maxDepth = 6
	for i := 0; i < maxDepth; i++ {
		p := filepath.Join(dir, FileName)
		if fileExists(p) {
			return p, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			break
		}
		dir = parent
	}
	return "", false
}

func fileExists(p string) bool {
	st, err := os.Stat(p)
	return err == nil && !st.IsDir()
}

// parse reads the documented subset: nested maps of scalar values, two-space
// indentation, no lists. Anything else is an error naming the line, because
// the failure being avoided is a typo that parses into silence.
func parse(r io.Reader, path string) (*Contract, error) {
	c := &Contract{Path: path, values: map[string]string{}}

	var stack []string
	depth := 0

	sc := bufio.NewScanner(r)
	line := 0
	for sc.Scan() {
		line++
		raw := sc.Text()

		if strings.TrimSpace(raw) == "" || strings.HasPrefix(strings.TrimSpace(raw), "#") {
			continue
		}
		if strings.ContainsRune(raw, '\t') {
			return nil, fmt.Errorf("%s:%d: tab indentation is not allowed", path, line)
		}

		// A comment after a value. Contract values are versions, "null" and
		// single words, none of which contain " #".
		if i := strings.Index(raw, " #"); i >= 0 {
			raw = raw[:i]
		}
		raw = strings.TrimRight(raw, " ")
		if raw == "" {
			continue
		}

		indent := len(raw) - len(strings.TrimLeft(raw, " "))
		if indent%2 != 0 {
			return nil, fmt.Errorf("%s:%d: indentation must be a multiple of two spaces", path, line)
		}
		level := indent / 2
		if level > depth {
			return nil, fmt.Errorf("%s:%d: unexpected indentation — no parent key at this level", path, line)
		}

		rest := raw[indent:]
		colon := strings.Index(rest, ":")
		if colon < 1 || !validKey(rest[:colon]) {
			return nil, fmt.Errorf("%s:%d: expected %q or %q", path, line, "key:", "key: value")
		}

		key := rest[:colon]
		value := strings.TrimLeft(rest[colon+1:], " ")

		stack = append(stack[:level], key)

		if value == "" {
			// A map opens one level of nesting.
			depth = level + 1
			continue
		}

		value = strings.Trim(value, `"`)
		full := strings.Join(stack, ".")
		if _, seen := c.values[full]; !seen {
			c.order = append(c.order, full)
		}
		c.values[full] = value

		// A leaf takes no children, so the next line may not indent past it.
		depth = level
	}
	if err := sc.Err(); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}

	return c, nil
}

func validKey(s string) bool {
	if s == "" {
		return false
	}
	for i, r := range s {
		switch {
		case r >= 'a' && r <= 'z', r >= 'A' && r <= 'Z', r == '_':
		case i > 0 && r >= '0' && r <= '9':
		default:
			return false
		}
	}
	return true
}
