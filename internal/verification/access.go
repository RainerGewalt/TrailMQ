package verification

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/RainerGewalt/TrailMQ/internal/mqtt"
)

// connect opens an authenticated MQTT session over TLS against the broker.
func (e *Environment) connect(ctx context.Context, id Identity) (*mqtt.Client, error) {
	return mqtt.Connect(ctx, mqtt.Options{
		Address:  e.Endpoints.MQTTOverTLS(),
		ClientID: id.ClientID,
		Username: id.Username,
		Password: id.Password,
		CACert:   e.caCert,
		// The demo certificate is issued for localhost among other names, and
		// the address may carry a non-default port.
		ServerName: "localhost",
		Timeout:    15 * time.Second,
	})
}

// AuthenticatedMQTT proves the TLS listener accepts a valid identity.
//
// It subscribes as well as connecting: a broker that accepts a connection but
// refuses every subscription has not demonstrated a usable listener.
func (e *Environment) AuthenticatedMQTT(ctx context.Context, id Identity) Result {
	const key, title = "tls_listener", "MQTT TLS listener accepts authenticated clients"

	client, err := e.connect(ctx, id)
	if err != nil {
		return fail(key, title, "TLS connect or authentication failed on "+
			e.Endpoints.MQTTOverTLS()+": "+firstLine(err.Error()))
	}
	defer client.Close()

	if err := client.Subscribe(ctx, "trailmq/#", 0); err != nil {
		return fail(key, title, "connected, but subscribing failed: "+firstLine(err.Error()))
	}
	return pass(key, title)
}

// DeliverySpec describes one publish and the observation that proves it
// arrived.
type DeliverySpec struct {
	Publisher  Identity
	Subscriber Identity
	// Filter is what the subscriber listens on; Topic is what the publisher
	// sends to. They differ so a scenario can prove a wildcard subscription
	// receives a specific topic.
	Filter  string
	Topic   string
	Payload []byte
	// Wait bounds how long delivery may take.
	Wait time.Duration
}

func (s DeliverySpec) wait() time.Duration {
	if s.Wait <= 0 {
		return 15 * time.Second
	}
	return s.Wait
}

// PublishAndObserve proves an authorized publish reaches a subscriber.
//
// The distinction this makes is the whole point: the payload is observed
// arriving at a second, independently authenticated client, not merely
// acknowledged by the broker. "Accepted" and "delivered" are different claims,
// and only the second one says the message got somewhere.
func (e *Environment) PublishAndObserve(ctx context.Context, spec DeliverySpec) Result {
	const key = "allow"
	title := "Authorized publish reached the subscriber"

	subscriber, err := e.connect(ctx, spec.Subscriber)
	if err != nil {
		return fail(key, title, "the subscriber could not connect: "+firstLine(err.Error()))
	}
	defer subscriber.Close()

	if err := subscriber.Subscribe(ctx, spec.Filter, 1); err != nil {
		return fail(key, title, "the subscriber could not subscribe to "+spec.Filter+
			": "+firstLine(err.Error()))
	}

	publisher, err := e.connect(ctx, spec.Publisher)
	if err != nil {
		return fail(key, title, "the publisher could not connect: "+firstLine(err.Error()))
	}
	defer publisher.Close()

	if err := publisher.Publish(ctx, spec.Topic, spec.Payload, 1); err != nil {
		if errors.Is(err, mqtt.ErrRefused) {
			return fail(key, title, "the broker refused a publish that should have been allowed: "+
				spec.Publisher.Username+" → "+spec.Topic)
		}
		return fail(key, title, "publishing failed: "+firstLine(err.Error()))
	}

	// Messages other than the one under test can arrive on a wildcard filter,
	// so the payload is matched rather than the first delivery counted.
	deadline := time.Now().Add(spec.wait())
	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return fail(key, title, "nothing arrived on "+spec.Filter+
				" within "+spec.wait().String())
		}

		msg, err := subscriber.Receive(ctx, remaining)
		if err != nil {
			return fail(key, title, "nothing arrived on "+spec.Filter+": "+firstLine(err.Error()))
		}
		if msg.Topic == spec.Topic && bytes.Equal(msg.Payload, spec.Payload) {
			return pass(key, title).withFact("delivered_topic", msg.Topic)
		}
	}
}

// DenialSpec describes a publish the access policy is expected to refuse.
type DenialSpec struct {
	Publisher Identity
	Topic     string
	Payload   []byte
}

// ExpectPublishDenied proves the broker enforces a refusal.
//
// The success case here is the broker *not* accepting: TrailMQ withholds the
// acknowledgement for a publish its policy denies, and may close the
// connection instead. Either outcome is enforcement. What must not happen is a
// clean acknowledgement, which would mean the message was accepted.
func (e *Environment) ExpectPublishDenied(ctx context.Context, spec DenialSpec) Result {
	const key, title = "deny", "Unauthorized publish was blocked"

	client, err := e.connect(ctx, spec.Publisher)
	if err != nil {
		if errors.Is(err, mqtt.ErrNotAuthorized) {
			// Refused at the door rather than at the topic. Still a denial,
			// but a different one, and saying so keeps the report honest.
			return pass(key, title).withFact("denied_at", "connect")
		}
		return fail(key, title, "could not connect to attempt the publish: "+firstLine(err.Error()))
	}
	defer client.Close()

	err = client.Publish(ctx, spec.Topic, spec.Payload, 1)
	switch {
	case err == nil:
		return fail(key, title,
			spec.Topic+" accepted a publish from "+spec.Publisher.Username)
	case errors.Is(err, mqtt.ErrRefused), errors.Is(err, mqtt.ErrClosed):
		return pass(key, title).withFact("denied_at", "publish")
	default:
		return fail(key, title, "the publish failed for an unrelated reason: "+firstLine(err.Error()))
	}
}

// Payload builds a payload that is unique to this run, so an observation
// cannot be satisfied by a retained or replayed message from an earlier one.
func Payload(format string, args ...any) []byte {
	return []byte(fmt.Sprintf(format, args...))
}
