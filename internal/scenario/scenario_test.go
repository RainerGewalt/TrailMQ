package scenario

import (
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The scenarios this repository ships have to load and validate, or the demo
// is broken for everyone who downloads it.
func TestShippedScenariosAreValid(t *testing.T) {
	dir := filepath.Join("..", "..", "scenarios")
	scenarios, err := LoadAll(dir)
	if err != nil {
		t.Fatalf("the shipped scenario pack does not load: %v", err)
	}
	if len(scenarios) == 0 {
		t.Fatal("no scenarios found")
	}

	for _, sc := range scenarios {
		// The file name is how a user names a scenario on the command line
		// and how a URL addresses it on the website. If it disagrees with the
		// id, one of the two is wrong.
		base := strings.TrimSuffix(filepath.Base(sc.Path), ".json")
		if base != sc.ID {
			t.Errorf("%s: id is %q", base, sc.ID)
		}
	}
}

func TestUnauthorizedMachineCommandTellsTheWholeStory(t *testing.T) {
	sc, err := Load(filepath.Join("..", "..", "scenarios", "unauthorized-machine-command.json"))
	if err != nil {
		t.Fatal(err)
	}

	// This is the scenario the product leads with, so it has to carry both
	// halves of the claim: the command was refused, and the refusal was
	// recorded attributably. Either alone is a weaker product.
	var denied, recorded bool
	for _, step := range sc.Steps {
		switch step.Kind {
		case PublishDenied:
			denied = true
		case DecisionRecord:
			recorded = true
		}
	}
	if !denied || !recorded {
		t.Errorf("scenario has denied=%v recorded=%v, want both", denied, recorded)
	}

	// Level 1 must be readable without MQTT vocabulary. The audience for this
	// scenario includes people who do not work with brokers.
	for _, step := range sc.Steps {
		for _, jargon := range []string{"MQTT", "QoS", "PUBACK", "broker", "topic filter"} {
			if strings.Contains(step.Headline, jargon) {
				t.Errorf("step %q headline uses %q, which the first disclosure level should not need: %q",
					step.ID, jargon, step.Headline)
			}
		}
	}
}

func TestValidateRequiresEveryDisclosureLevel(t *testing.T) {
	cases := map[string]func(*Scenario){
		"no headline":    func(s *Scenario) { s.Steps[0].Headline = "" },
		"no explanation": func(s *Scenario) { s.Steps[0].Explanation = "" },
		"no closing":     func(s *Scenario) { s.Closing.Explanation = "" },
		"no question":    func(s *Scenario) { s.Question = "" },
		"no summary":     func(s *Scenario) { s.Summary = "" },
		// A scenario that does not say which runtime it describes will
		// eventually describe one that no longer behaves that way.
		"no compatibility": func(s *Scenario) { s.CompatibleWith = "" },
		"no steps":         func(s *Scenario) { s.Steps = nil },
	}

	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			sc := validScenario()
			mutate(sc)
			if err := sc.Validate(); err == nil {
				t.Errorf("Validate accepted a scenario with %s", name)
			}
		})
	}
}

func TestValidateRejectsBrokenStepReferences(t *testing.T) {
	cases := map[string]func(*Scenario){
		"undefined actor": func(s *Scenario) { s.Steps[0].Actor = "nobody" },
		"unknown kind":    func(s *Scenario) { s.Steps[0].Kind = "publish_maybe" },
		"no topic":        func(s *Scenario) { s.Steps[0].Topic = "" },
		"duplicate ids":   func(s *Scenario) { s.Steps = append(s.Steps, s.Steps[0]) },
		"delivery without observer": func(s *Scenario) {
			s.Steps[0].Kind = PublishDelivered
			s.Steps[0].Filter = "public/#"
		},
	}

	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			sc := validScenario()
			mutate(sc)
			if err := sc.Validate(); err == nil {
				t.Errorf("Validate accepted a scenario with %s", name)
			}
		})
	}
}

// A hand-edited scenario with a mistyped field would otherwise load with that
// field silently missing, producing a step that never runs.
func TestLoadRejectsUnknownFields(t *testing.T) {
	sc := validScenario()
	raw, err := json.Marshal(sc)
	if err != nil {
		t.Fatal(err)
	}

	var asMap map[string]any
	if err := json.Unmarshal(raw, &asMap); err != nil {
		t.Fatal(err)
	}
	asMap["headlne"] = "typo"
	raw, _ = json.Marshal(asMap)

	path := filepath.Join(t.TempDir(), "typo.json")
	if err := os.WriteFile(path, raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := Load(path); err == nil {
		t.Error("Load accepted a scenario with an unknown field")
	}
}

func TestLoadAllOnAMissingDirectory(t *testing.T) {
	// An installation without a scenario pack is a state to report, not to
	// crash on.
	scenarios, err := LoadAll(filepath.Join(t.TempDir(), "absent"))
	if err != nil {
		t.Errorf("LoadAll on a missing directory returned %v", err)
	}
	if len(scenarios) != 0 {
		t.Errorf("got %d scenarios", len(scenarios))
	}
}

func validScenario() *Scenario {
	return &Scenario{
		ID:             "example",
		Title:          "Example",
		Question:       "What happens?",
		Summary:        "Something happens.",
		CompatibleWith: "3.1.0",
		Actors: []Actor{
			{Key: "operator", Client: "line07-hmi", Identity: "testuser", Description: "Panel"},
		},
		Steps: []Step{
			{
				ID:          "blocked",
				Kind:        PublishDenied,
				Actor:       "operator",
				Topic:       "restricted/line07/control/setpoint",
				Headline:    "Machine command blocked",
				Explanation: "The panel may not write there.",
			},
		},
		Closing: Closing{Headline: "So", Explanation: "That is the difference."},
	}
}
