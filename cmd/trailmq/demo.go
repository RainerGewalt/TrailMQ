package main

import (
	"context"
	"path/filepath"

	"github.com/RainerGewalt/TrailMQ/internal/output"
	"github.com/RainerGewalt/TrailMQ/internal/scenario"
	"github.com/RainerGewalt/TrailMQ/internal/verification"
)

// ScenarioDir is where the scenario pack lives inside an installation.
const ScenarioDir = "scenarios"

// cmdDemo runs a scenario against the local evaluation.
//
// The demo and `verify` share every probe underneath, and differ only in what
// they are for. verify answers "does this release honour its promise?" as
// PASS/FAIL. A demo answers "what does TrailMQ do, in a situation I
// recognise?" — the same events, told so that someone who does not work with
// MQTT can follow them.
//
// Output is disclosed in three levels: what happened, why it happened, and the
// identities and topics behind it. --technical opens the third level for every
// step at once, for a reader who wants the record rather than the story.
func cmdDemo(out, errOut *output.Printer, args []string) int {
	technical := false
	var wanted string

	for _, arg := range args {
		switch arg {
		case "--technical":
			technical = true
		default:
			if wanted != "" {
				errOut.Fail("Only one scenario can be run at a time.")
				return exitUsage
			}
			wanted = arg
		}
	}

	// Listing what ships with this installation is a property of the
	// installation, not of a running stack. A fresh install should be able to
	// answer "what can I run?" before anything is set up — that is the first
	// question someone asks after installing, and refusing it with "run
	// quickstart first" teaches nothing about what quickstart would lead to.
	// Running a scenario still needs a prepared recipe, so the requirement
	// moves to the case that actually has it.
	s, err := openSession(wanted != "")
	if err != nil {
		return reportSetupError(errOut, err)
	}

	scenarios, err := scenario.LoadAll(filepath.Join(s.layout.Install, ScenarioDir))
	if err != nil {
		errOut.Fail("The scenario pack could not be read.")
		errOut.Detail(err.Error())
		return exitFailure
	}
	if len(scenarios) == 0 {
		errOut.Fail("This installation carries no scenarios.")
		return exitFailure
	}

	if wanted == "" {
		listScenarios(out, scenarios)
		return exitOK
	}

	var chosen *scenario.Scenario
	for _, sc := range scenarios {
		if sc.ID == wanted {
			chosen = sc
			break
		}
	}
	if chosen == nil {
		errOut.Fail("No scenario called %q.", wanted)
		errOut.Blank()
		listScenarios(errOut, scenarios)
		return exitUsage
	}

	// A scenario written against a different runtime may describe behaviour
	// this one no longer has. Saying so is better than narrating an outcome
	// that did not happen.
	if version, err := s.contract.Version(); err == nil && chosen.CompatibleWith != version {
		out.Warn("This scenario was written for TrailMQ %s, and you are running %s.",
			chosen.CompatibleWith, version)
		out.Blank()
	}

	ctx := context.Background()
	if !requireDocker(ctx, errOut) {
		return exitEnvironment
	}

	env, err := verification.Open(ctx, s.recipe, s.points, s.project)
	if err != nil {
		errOut.Fail("The evaluation is not running.")
		errOut.Detail(err.Error())
		errOut.Detail("Run 'trailmq quickstart' first.")
		return exitEnvironment
	}

	return presentScenario(ctx, out, errOut, s, chosen, env, technical)
}

func presentScenario(
	ctx context.Context,
	out, errOut *output.Printer,
	s *session,
	sc *scenario.Scenario,
	env *verification.Environment,
	technical bool,
) int {
	out.Title(sc.Title)
	out.Dim("%s", sc.Question)
	out.Blank()
	out.Println(wrap(sc.Summary, 76))

	if len(sc.Topology) > 0 {
		out.Blank()
		for i, node := range sc.Topology {
			if i > 0 {
				out.Println("      │")
				out.Println("      ▼")
			}
			out.Printf("  %s\n", node)
		}
	}
	out.Blank()

	outcomes, err := scenario.Run(ctx, sc, env)
	if err != nil {
		errOut.Fail("The scenario could not be run.")
		errOut.Detail(err.Error())
		return exitFailure
	}

	failed := false
	for _, outcome := range outcomes {
		out.Blank()
		if outcome.Succeeded() {
			out.OK("%s", outcome.Step.Headline)
		} else {
			failed = true
			out.Fail("%s did not happen", outcome.Step.Headline)
			if outcome.Result.Detail != "" {
				out.Detail(outcome.Result.Detail)
			}
			continue
		}

		out.Detail(wrap(outcome.Step.Explanation, 72))

		if technical {
			out.Blank()
			for _, field := range outcome.Technical {
				out.Field(field.Label, field.Value)
			}
			if outcome.Step.TechnicalNote != "" {
				out.Detail(wrap(outcome.Step.TechnicalNote, 72))
			}
		}
	}

	out.Blank()
	if failed {
		out.Fail("The scenario did not complete.")
		out.Dim("Run 'trailmq verify' to see which product check is failing.")
		return exitFailure
	}

	out.Title(sc.Closing.Headline)
	out.Println(wrap(sc.Closing.Explanation, 76))
	if sc.Closing.Next != "" {
		out.Blank()
		out.Printf("  %s\n", sc.Closing.Next)
		out.Printf("  %s\n", out.Link(s.points.WebUI()))
	}
	if !technical {
		out.Blank()
		out.Dim("Run with --technical to see the identities, topics and decisions.")
	}
	return exitOK
}

func listScenarios(p *output.Printer, scenarios []*scenario.Scenario) {
	p.Title("Scenarios")
	for _, sc := range scenarios {
		p.Field(sc.ID, sc.Title)
		p.Detail(sc.Question)
	}
	p.Blank()
	p.Dim("Run one with: trailmq demo <scenario>")
}

// wrap breaks text at a column so an explanation stays readable in a terminal
// without the scenario file having to carry line breaks — the same text is
// rendered very differently on a web page.
func wrap(text string, width int) string {
	var out []byte
	column := 0
	start := 0

	for i := 0; i <= len(text); i++ {
		if i < len(text) && text[i] != ' ' {
			continue
		}
		word := text[start:i]
		if column > 0 && column+1+len(word) > width {
			out = append(out, '\n')
			column = 0
		} else if column > 0 {
			out = append(out, ' ')
			column++
		}
		out = append(out, word...)
		column += len(word)
		start = i + 1
	}
	return string(out)
}
