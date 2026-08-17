// Package scenario models TrailMQ's demonstrable situations.
//
// A scenario is a business situation with a technical outcome, defined once
// and told the same way everywhere. The launcher runs it against a real
// evaluation; the website presents the same file as a walkthrough. That shared
// definition is the point: a product story the evaluation cannot reproduce is
// a claim, not a demonstration.
//
// Scenarios are JSON rather than YAML. The release contract's reader
// deliberately accepts only nested maps of scalars, and a scenario needs
// ordered lists of steps — supporting those would mean either a dependency or
// a second hand-written parser, in a format the website would then have to
// parse again. JSON is read by the standard library here and natively in a
// browser, and it is strict about the shapes this contract depends on.
//
// Every scenario carries three levels of disclosure, because the audience is
// not one audience: a production engineer, a quality reviewer and an MQTT
// specialist need the same event described at different depths.
//
//	headline        what happened, in one line, no MQTT vocabulary
//	explanation     why it happened, in the language of the situation
//	technical       the identities, topics, decisions and reasons
package scenario

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

// Kind is what a step does. Each maps onto verification probes, so a scenario
// can only demonstrate something the product proof can also assert.
type Kind string

const (
	// PublishDenied expects the access policy to refuse a publish.
	PublishDenied Kind = "publish_denied"
	// PublishDelivered expects a publish to reach a subscriber.
	PublishDelivered Kind = "publish_delivered"
	// DecisionRecord expects an attributable record for a refused action.
	DecisionRecord Kind = "decision_record"
)

// Actor is a participant, described for a reader and bound to a real
// evaluation identity.
//
// Client is the MQTT client identifier, which the client itself chooses and
// which appears in the decision record. That is what lets a scenario speak in
// plant vocabulary — "line07-hmi" — while remaining exactly reproducible: the
// identity behind it is a real evaluation user, and the scenario never invents
// one that does not exist.
type Actor struct {
	Key         string `json:"key"`
	Client      string `json:"client"`
	Identity    string `json:"identity"`
	Description string `json:"description"`
}

// Step is one observable event.
type Step struct {
	ID    string `json:"id"`
	Kind  Kind   `json:"kind"`
	Actor string `json:"actor"`
	// Observer subscribes for a delivery step. Empty means the scenario needs
	// no second client.
	Observer string `json:"observer,omitempty"`
	Topic    string `json:"topic"`
	Filter   string `json:"filter,omitempty"`
	Payload  string `json:"payload,omitempty"`

	Headline      string `json:"headline"`
	Explanation   string `json:"explanation"`
	TechnicalNote string `json:"technicalNote,omitempty"`
}

// Closing is what the reader should take away.
type Closing struct {
	Headline    string `json:"headline"`
	Explanation string `json:"explanation"`
	Next        string `json:"next,omitempty"`
}

type Scenario struct {
	ID       string `json:"id"`
	Title    string `json:"title"`
	Audience string `json:"audience"`
	Question string `json:"question"`
	// CompatibleWith is the runtime release this scenario was written
	// against. A scenario that quietly outlives the behaviour it describes is
	// worse than no scenario, so the gate holds this to the release contract.
	CompatibleWith string `json:"compatibleWith"`

	Summary  string   `json:"summary"`
	Topology []string `json:"topology"`
	Actors   []Actor  `json:"actors"`
	Steps    []Step   `json:"steps"`
	Closing  Closing  `json:"closing"`

	// Path is where the scenario was loaded from.
	Path string `json:"-"`
}

// Actor resolves a step's participant.
func (s *Scenario) Actor(key string) (Actor, bool) {
	for _, a := range s.Actors {
		if a.Key == key {
			return a, true
		}
	}
	return Actor{}, false
}

// Load reads and validates one scenario file.
func Load(path string) (*Scenario, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var sc Scenario
	decoder := json.NewDecoder(strings.NewReader(string(data)))
	// An unknown field is almost always a typo in a hand-edited file, and a
	// silently ignored one turns into a step that never runs.
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&sc); err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	sc.Path = path

	if err := sc.Validate(); err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	return &sc, nil
}

// LoadAll reads every scenario in a directory, in a stable order.
func LoadAll(dir string) ([]*Scenario, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		if os.IsNotExist(err) {
			return nil, nil
		}
		return nil, err
	}

	var scenarios []*Scenario
	for _, entry := range entries {
		if entry.IsDir() || filepath.Ext(entry.Name()) != ".json" {
			continue
		}
		sc, err := Load(filepath.Join(dir, entry.Name()))
		if err != nil {
			return nil, err
		}
		scenarios = append(scenarios, sc)
	}

	sort.Slice(scenarios, func(i, j int) bool { return scenarios[i].ID < scenarios[j].ID })
	return scenarios, nil
}

// Validate enforces the parts of the contract that make a scenario usable by
// both the launcher and the website.
//
// The disclosure levels are required rather than optional. A step with no
// headline reads as MQTT trivia to the audience this exists for, and one with
// no explanation cannot answer the question the scenario claims to answer.
func (s *Scenario) Validate() error {
	if s.ID == "" {
		return fmt.Errorf("the scenario has no id")
	}
	if s.Title == "" || s.Question == "" || s.Summary == "" {
		return fmt.Errorf("%s: title, question and summary are all required", s.ID)
	}
	if s.CompatibleWith == "" {
		return fmt.Errorf("%s: compatibleWith must name the runtime release this was written against", s.ID)
	}
	if len(s.Steps) == 0 {
		return fmt.Errorf("%s: a scenario with no steps demonstrates nothing", s.ID)
	}
	if s.Closing.Headline == "" || s.Closing.Explanation == "" {
		return fmt.Errorf("%s: the closing needs a headline and an explanation", s.ID)
	}

	seen := map[string]bool{}
	for i, step := range s.Steps {
		where := fmt.Sprintf("%s: step %d", s.ID, i+1)
		if step.ID == "" {
			return fmt.Errorf("%s has no id", where)
		}
		if seen[step.ID] {
			return fmt.Errorf("%s: duplicate step id %q", s.ID, step.ID)
		}
		seen[step.ID] = true

		if step.Headline == "" || step.Explanation == "" {
			return fmt.Errorf("%s (%s) needs both a headline and an explanation", where, step.ID)
		}
		if step.Topic == "" {
			return fmt.Errorf("%s (%s) names no topic", where, step.ID)
		}

		switch step.Kind {
		case PublishDenied:
			if err := s.requireActor(where, step.Actor); err != nil {
				return err
			}
		case PublishDelivered:
			if err := s.requireActor(where, step.Actor); err != nil {
				return err
			}
			if err := s.requireActor(where, step.Observer); err != nil {
				return err
			}
			if step.Filter == "" {
				return fmt.Errorf("%s (%s) needs a filter for the observer to subscribe to", where, step.ID)
			}
		case DecisionRecord:
			// Reads the record a previous step produced; needs no actor.
		default:
			return fmt.Errorf("%s (%s): unknown step kind %q", where, step.ID, step.Kind)
		}
	}

	for _, a := range s.Actors {
		if a.Key == "" || a.Identity == "" || a.Client == "" {
			return fmt.Errorf("%s: actor %q needs a key, an identity and a client id", s.ID, a.Key)
		}
	}
	return nil
}

func (s *Scenario) requireActor(where, key string) error {
	if key == "" {
		return fmt.Errorf("%s names no actor", where)
	}
	if _, ok := s.Actor(key); !ok {
		return fmt.Errorf("%s refers to actor %q, which the scenario does not define", where, key)
	}
	return nil
}
