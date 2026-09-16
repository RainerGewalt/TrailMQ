package scenario

import (
	"context"
	"fmt"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/verification"
)

// Outcome is what running one step produced.
//
// It carries both the narrative from the scenario file and the observation
// from the probe, so a presenter can show either without re-deriving one from
// the other.
type Outcome struct {
	Step Step
	// Actor is the participant, when the step had one.
	Actor Actor
	// Result is the probe's observation.
	Result verification.Result
	// Technical is the disclosure-level-3 detail, as ordered label/value
	// pairs. Ordered because it is read as a record, not a map.
	Technical []Field
}

type Field struct {
	Label string
	Value string
}

func (o Outcome) Succeeded() bool { return o.Result.Passed() }

// Run executes a scenario against a running evaluation.
//
// Every step goes through the verification probes rather than through
// scenario-specific code. That is what keeps a demonstration honest: the demo
// can only show what the product proof can also assert, and the two cannot
// drift into telling different stories about the same behaviour.
func Run(ctx context.Context, sc *Scenario, env *verification.Environment) ([]Outcome, error) {
	outcomes := make([]Outcome, 0, len(sc.Steps))

	for _, step := range sc.Steps {
		outcome, err := runStep(ctx, sc, env, step)
		if err != nil {
			return outcomes, err
		}
		outcomes = append(outcomes, outcome)

		// A scenario is a narrative: once one step has not happened, the
		// following ones would describe consequences of an event that did not
		// occur.
		if !outcome.Succeeded() {
			break
		}
	}
	return outcomes, nil
}

func runStep(ctx context.Context, sc *Scenario, env *verification.Environment, step Step) (Outcome, error) {
	outcome := Outcome{Step: step}

	switch step.Kind {
	case PublishDenied:
		actor, id, err := identity(sc, env, step.Actor)
		if err != nil {
			return outcome, err
		}
		outcome.Actor = actor

		outcome.Result = env.ExpectPublishDenied(ctx, verification.DenialSpec{
			Publisher: id,
			Topic:     step.Topic,
			Payload:   []byte(step.Payload),
		})
		outcome.Technical = []Field{
			{"Client", actor.Client},
			{"Identity", actor.Identity},
			{"Action", "publish"},
			{"Topic", step.Topic},
			{"Decision", decisionWord(outcome.Result.Passed(), "DENIED", "ALLOWED")},
		}
		if where, ok := outcome.Result.Facts["denied_at"]; ok {
			outcome.Technical = append(outcome.Technical, Field{"Refused at", where})
		}

	case PublishDelivered:
		actor, publisher, err := identity(sc, env, step.Actor)
		if err != nil {
			return outcome, err
		}
		outcome.Actor = actor

		_, observer, err := identity(sc, env, step.Observer)
		if err != nil {
			return outcome, err
		}

		payload := []byte(step.Payload)
		outcome.Result = env.PublishAndObserve(ctx, verification.DeliverySpec{
			Publisher:  publisher,
			Subscriber: observer,
			Filter:     step.Filter,
			Topic:      step.Topic,
			Payload:    payload,
		})
		outcome.Technical = []Field{
			{"Client", actor.Client},
			{"Identity", actor.Identity},
			{"Action", "publish"},
			{"Topic", step.Topic},
			{"Observed on", step.Filter},
			{"Decision", decisionWord(outcome.Result.Passed(), "ALLOWED", "NOT DELIVERED")},
		}

	case DecisionRecord:
		outcome.Result = env.FindDecisionRecord(ctx, step.Topic, 10*time.Second)
		outcome.Technical = []Field{{"Topic", step.Topic}}
		if record, ok := outcome.Result.Facts["deny_record"]; ok {
			outcome.Technical = append(outcome.Technical, Field{"Record", record})
		}

	default:
		return outcome, fmt.Errorf("step %q has unknown kind %q", step.ID, step.Kind)
	}

	return outcome, nil
}

// identity binds a scenario actor to a real evaluation identity, using the
// scenario's client id so the decision record carries the plant-facing name.
func identity(sc *Scenario, env *verification.Environment, key string) (Actor, verification.Identity, error) {
	actor, ok := sc.Actor(key)
	if !ok {
		return Actor{}, verification.Identity{}, fmt.Errorf("the scenario does not define actor %q", key)
	}

	id, err := env.Identity(actor.Identity, actor.Client)
	if err != nil {
		return actor, verification.Identity{}, fmt.Errorf(
			"actor %q needs the evaluation identity %q: %w", actor.Key, actor.Identity, err)
	}
	return actor, id, nil
}

func decisionWord(ok bool, expected, unexpected string) string {
	if ok {
		return expected
	}
	return unexpected
}
