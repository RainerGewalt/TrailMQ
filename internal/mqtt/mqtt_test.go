package mqtt

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/binary"
	"encoding/pem"
	"errors"
	"math/big"
	"net"
	"testing"
	"time"
)

func TestRemainingLengthRoundTrip(t *testing.T) {
	// The boundaries of MQTT's variable-length encoding, where an off-by-one
	// corrupts every following byte of the stream.
	for _, n := range []int{0, 1, 127, 128, 16383, 16384, 2097151, 2097152} {
		encoded := encodeRemainingLength(n)
		got, err := readRemainingLength(newReader(encoded))
		if err != nil {
			t.Fatalf("length %d: %v", n, err)
		}
		if got != n {
			t.Errorf("length %d round-tripped to %d", n, got)
		}
	}
}

func TestDecodePublish(t *testing.T) {
	var body []byte
	body = appendString(body, "public/demo/temperature")
	body = binary.BigEndian.AppendUint16(body, 42)
	body = append(body, []byte(`{"value":21.4}`)...)

	msg, id, err := decodePublish(0x02 /* qos 1 */, body)
	if err != nil {
		t.Fatal(err)
	}
	if msg.Topic != "public/demo/temperature" {
		t.Errorf("topic = %q", msg.Topic)
	}
	if id != 42 {
		t.Errorf("packet id = %d, want 42", id)
	}
	if string(msg.Payload) != `{"value":21.4}` {
		t.Errorf("payload = %q", msg.Payload)
	}
}

func TestDecodePublishQoS0CarriesNoPacketID(t *testing.T) {
	var body []byte
	body = appendString(body, "public/x")
	body = append(body, []byte("hello")...)

	msg, id, err := decodePublish(0, body)
	if err != nil {
		t.Fatal(err)
	}
	// Reading a packet identifier that is not there would eat the first two
	// bytes of the payload.
	if id != 0 || string(msg.Payload) != "hello" {
		t.Errorf("id = %d, payload = %q", id, msg.Payload)
	}
}

func TestDecodePublishRejectsTruncatedPackets(t *testing.T) {
	for name, body := range map[string][]byte{
		"no topic length": {0x00},
		"short topic":     {0x00, 0x10, 'a'},
	} {
		if _, _, err := decodePublish(0, body); err == nil {
			t.Errorf("%s: accepted a truncated packet", name)
		}
	}
}

// --- against a fake broker --------------------------------------------------

func TestConnectPublishAndReceive(t *testing.T) {
	broker := startBroker(t, brokerBehaviour{connack: 0, ackPublish: true})

	client, err := Connect(context.Background(), broker.options("prober"))
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer client.Close()

	if err := client.Subscribe(context.Background(), "public/#", 1); err != nil {
		t.Fatalf("Subscribe: %v", err)
	}
	if err := client.Publish(context.Background(), "public/demo", []byte("payload"), 1); err != nil {
		t.Fatalf("Publish: %v", err)
	}

	// The fake broker echoes what it receives, which is what proves the
	// receive path decodes a real PUBLISH rather than a synthetic one.
	msg, err := client.Receive(context.Background(), 5*time.Second)
	if err != nil {
		t.Fatalf("Receive: %v", err)
	}
	if msg.Topic != "public/demo" || string(msg.Payload) != "payload" {
		t.Errorf("received %q on %q", msg.Payload, msg.Topic)
	}
}

// A refused identity must be reported as a decision, not as a transport
// failure — the difference between "the policy worked" and "nothing was
// proven".
func TestConnectReportsRefusedIdentity(t *testing.T) {
	for _, code := range []byte{4, 5} {
		broker := startBroker(t, brokerBehaviour{connack: code})
		_, err := Connect(context.Background(), broker.options("prober"))
		if !errors.Is(err, ErrNotAuthorized) {
			t.Errorf("CONNACK %d gave %v, want ErrNotAuthorized", code, err)
		}
	}
}

// TrailMQ withholds the acknowledgement for a publish its policy denies. That
// is the signal the deny probe reads, so it must surface as ErrRefused rather
// than as a generic timeout.
func TestPublishWithoutAcknowledgementIsRefused(t *testing.T) {
	broker := startBroker(t, brokerBehaviour{connack: 0, ackPublish: false, closeOnPublish: true})

	client, err := Connect(context.Background(), broker.options("prober"))
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer client.Close()

	err = client.Publish(context.Background(), "restricted/ops/config", []byte("nope"), 1)
	if !errors.Is(err, ErrRefused) && !errors.Is(err, ErrClosed) {
		t.Errorf("Publish gave %v, want ErrRefused or ErrClosed", err)
	}
}

func TestPublishQoS0DoesNotWaitForAcknowledgement(t *testing.T) {
	broker := startBroker(t, brokerBehaviour{connack: 0, ackPublish: false})

	client, err := Connect(context.Background(), broker.options("prober"))
	if err != nil {
		t.Fatalf("Connect: %v", err)
	}
	defer client.Close()

	done := make(chan error, 1)
	go func() { done <- client.Publish(context.Background(), "public/x", []byte("fire"), 0) }()

	select {
	case err := <-done:
		if err != nil {
			t.Errorf("QoS 0 publish failed: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Error("a QoS 0 publish waited for an acknowledgement")
	}
}

type brokerBehaviour struct {
	connack        byte
	ackPublish     bool
	closeOnPublish bool
}

type fakeBroker struct {
	addr   string
	caPEM  []byte
	closed chan struct{}
}

func (b *fakeBroker) options(clientID string) Options {
	return Options{
		Address:    b.addr,
		ClientID:   clientID,
		Username:   "testuser",
		Password:   "secret",
		CACert:     b.caPEM,
		ServerName: "localhost",
		Timeout:    5 * time.Second,
	}
}

// startBroker runs a TLS listener that speaks just enough MQTT to exercise the
// client. It is not a broker implementation; it is a way to assert the client
// puts the right bytes on the wire and reads the answers correctly.
func startBroker(t *testing.T, behaviour brokerBehaviour) *fakeBroker {
	t.Helper()

	certPEM, keyPEM := selfSigned(t)
	cert, err := tls.X509KeyPair(certPEM, keyPEM)
	if err != nil {
		t.Fatal(err)
	}

	listener, err := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{
		Certificates: []tls.Certificate{cert},
	})
	if err != nil {
		t.Fatal(err)
	}

	broker := &fakeBroker{
		addr:   listener.Addr().String(),
		caPEM:  certPEM,
		closed: make(chan struct{}),
	}
	t.Cleanup(func() { listener.Close() })

	go func() {
		conn, err := listener.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		serve(conn, behaviour)
	}()

	return broker
}

func serve(conn net.Conn, behaviour brokerBehaviour) {
	write := func(kind, flags byte, body []byte) error {
		packet := append([]byte{kind<<4 | flags}, encodeRemainingLength(len(body))...)
		_, err := conn.Write(append(packet, body...))
		return err
	}

	for {
		kind, _, body, err := readPacket(conn)
		if err != nil {
			return
		}

		switch kind {
		case pktCONNECT:
			if write(pktCONNACK, 0, []byte{0, behaviour.connack}) != nil || behaviour.connack != 0 {
				return
			}
		case pktSUBSCRIBE:
			if len(body) >= 2 {
				_ = write(pktSUBACK, 0, []byte{body[0], body[1], 1})
			}
		case pktPUBLISH:
			if behaviour.closeOnPublish {
				return
			}
			// The packet identifier sits after the topic.
			topicLen := int(binary.BigEndian.Uint16(body))
			id := body[2+topicLen : 4+topicLen]
			payload := body[4+topicLen:]

			if behaviour.ackPublish {
				if write(pktPUBACK, 0, id) != nil {
					return
				}
				// Echo it back so the receive path has something real to decode.
				var echo []byte
				echo = appendString(echo, string(body[2:2+topicLen]))
				echo = append(echo, payload...)
				_ = write(pktPUBLISH, 0, echo)
			}
		case pktDISCONNECT:
			return
		}
	}
}

func selfSigned(t *testing.T) (certPEM, keyPEM []byte) {
	t.Helper()

	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	template := &x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "localhost"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment | x509.KeyUsageCertSign,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames:              []string{"localhost"},
		IPAddresses:           []net.IP{net.ParseIP("127.0.0.1")},
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}

	certPEM = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM = pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	return certPEM, keyPEM
}

type sliceReader struct {
	data []byte
	pos  int
}

func newReader(b []byte) *sliceReader { return &sliceReader{data: b} }

func (r *sliceReader) Read(p []byte) (int, error) {
	if r.pos >= len(r.data) {
		return 0, errors.New("EOF")
	}
	n := copy(p, r.data[r.pos:])
	r.pos += n
	return n, nil
}
