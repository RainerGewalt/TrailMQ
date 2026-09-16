// Package mqtt is a minimal MQTT 3.1.1 client, enough to prove what TrailMQ
// claims and no more.
//
// Writing one rather than depending on a library or a container is a
// deliberate trade. The shell proof shells out to mosquitto_pub, falling back
// to `docker run eclipse-mosquitto` when it is not installed — which means an
// extra image pull, a container per publish, and a Windows evaluator needing
// tooling that is not part of the product. It also reduces every outcome to an
// exit code, so "the broker refused this" and "the network broke" look the
// same.
//
// Speaking the protocol directly gives the verification layer what it actually
// needs: the CONNACK return code, whether a QoS 1 publish was acknowledged,
// and whether the broker closed the connection — the difference between denied
// and undelivered.
//
// Implemented: CONNECT, SUBSCRIBE, PUBLISH and receive at QoS 0 and 1, PING,
// DISCONNECT. Not implemented: QoS 2, retained-message replay, will messages,
// persistent sessions. Those are not part of any claim being proven, and an
// unused feature is an untested one.
package mqtt

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"time"
)

// Packet types, from the MQTT 3.1.1 specification.
const (
	pktCONNECT     = 1
	pktCONNACK     = 2
	pktPUBLISH     = 3
	pktPUBACK      = 4
	pktSUBSCRIBE   = 8
	pktSUBACK      = 9
	pktPINGREQ     = 12
	pktPINGRESP    = 13
	pktDISCONNECT  = 14
	protocolLevel  = 4 // MQTT 3.1.1
	maxRemainingSz = 268435455
)

// ErrNotAuthorized reports that the broker refused the connection for this
// identity. It is distinct from a transport failure on purpose: one means the
// access policy worked, the other means nothing was proven.
var ErrNotAuthorized = errors.New("the broker refused this identity")

// ErrRefused reports a publish the broker did not acknowledge — either no
// PUBACK arrived, or the broker closed the connection instead.
var ErrRefused = errors.New("the broker did not accept the publish")

// ErrClosed reports that the broker closed the connection.
var ErrClosed = errors.New("the broker closed the connection")

type Options struct {
	// Address is host:port.
	Address string
	// ClientID identifies this client to the broker and appears in decision
	// records, which is what makes an action attributable.
	ClientID string
	Username string
	Password string
	// CACert is the PEM-encoded certificate authority. The evaluation uses
	// generated demo certificates, so the system trust store is not involved.
	CACert []byte
	// ServerName is the name verified in the broker's certificate. Empty means
	// the host part of Address.
	ServerName string
	// Timeout bounds connecting and every synchronous exchange.
	Timeout time.Duration
}

func (o Options) timeout() time.Duration {
	if o.Timeout <= 0 {
		return 15 * time.Second
	}
	return o.Timeout
}

// Message is an incoming application message.
type Message struct {
	Topic   string
	Payload []byte
	QoS     byte
}

type Client struct {
	conn net.Conn

	messages chan Message
	pubacks  chan uint16
	subacks  chan uint16

	mu       sync.Mutex
	nextID   uint16
	closed   bool
	readErr  error
	readDone chan struct{}
}

// Connect opens a TLS connection and completes the MQTT handshake.
func Connect(ctx context.Context, opts Options) (*Client, error) {
	pool := x509.NewCertPool()
	if len(opts.CACert) > 0 {
		if !pool.AppendCertsFromPEM(opts.CACert) {
			return nil, errors.New("the CA certificate could not be parsed")
		}
	}

	host, _, err := net.SplitHostPort(opts.Address)
	if err != nil {
		return nil, fmt.Errorf("address %q is not host:port: %w", opts.Address, err)
	}
	serverName := opts.ServerName
	if serverName == "" {
		serverName = host
	}

	dialer := &net.Dialer{Timeout: opts.timeout()}
	conn, err := tls.DialWithDialer(dialer, "tcp", opts.Address, &tls.Config{
		RootCAs:    pool,
		ServerName: serverName,
		MinVersion: tls.VersionTLS12,
	})
	if err != nil {
		return nil, fmt.Errorf("could not establish TLS to %s: %w", opts.Address, err)
	}

	c := &Client{
		conn:     conn,
		messages: make(chan Message, 32),
		pubacks:  make(chan uint16, 8),
		subacks:  make(chan uint16, 8),
		nextID:   1,
		readDone: make(chan struct{}),
	}

	if err := c.sendConnect(opts); err != nil {
		conn.Close()
		return nil, err
	}

	// CONNACK is read synchronously, before the reader goroutine starts, so a
	// refusal is reported as a refusal rather than as a closed connection.
	if err := c.readConnack(opts.timeout()); err != nil {
		conn.Close()
		return nil, err
	}

	go c.readLoop()
	return c, nil
}

func (c *Client) sendConnect(opts Options) error {
	var payload []byte
	payload = appendString(payload, opts.ClientID)

	flags := byte(0x02) // clean session
	if opts.Username != "" {
		flags |= 0x80
		payload = appendString(payload, opts.Username)
		if opts.Password != "" {
			flags |= 0x40
			payload = appendString(payload, opts.Password)
		}
	}

	var variable []byte
	variable = appendString(variable, "MQTT")
	variable = append(variable, protocolLevel, flags)
	variable = binary.BigEndian.AppendUint16(variable, 30) // keepalive seconds

	return c.send(pktCONNECT, 0, append(variable, payload...), opts.timeout())
}

func (c *Client) readConnack(timeout time.Duration) error {
	if err := c.conn.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		return err
	}
	kind, _, body, err := readPacket(c.conn)
	if err != nil {
		return fmt.Errorf("no CONNACK from the broker: %w", err)
	}
	if kind != pktCONNACK || len(body) < 2 {
		return fmt.Errorf("expected CONNACK, got packet type %d", kind)
	}

	switch code := body[1]; code {
	case 0:
		return nil
	case 4, 5:
		// 4 is bad credentials, 5 is not authorized. Both mean the broker
		// made an access decision, which is a result rather than a fault.
		return ErrNotAuthorized
	case 1:
		return errors.New("the broker rejected the MQTT protocol version")
	case 2:
		return errors.New("the broker rejected the client identifier")
	case 3:
		return errors.New("the broker is unavailable")
	default:
		return fmt.Errorf("the broker refused the connection (CONNACK code %d)", code)
	}
}

// readLoop dispatches incoming packets until the connection ends.
func (c *Client) readLoop() {
	defer close(c.readDone)
	for {
		// No deadline: the loop blocks until a packet arrives or the
		// connection closes. Callers impose their own timeouts.
		if err := c.conn.SetReadDeadline(time.Time{}); err != nil {
			c.setReadErr(err)
			return
		}

		kind, flags, body, err := readPacket(c.conn)
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, net.ErrClosed) {
				c.setReadErr(ErrClosed)
			} else {
				c.setReadErr(err)
			}
			return
		}

		switch kind {
		case pktPUBLISH:
			msg, packetID, err := decodePublish(flags, body)
			if err != nil {
				c.setReadErr(err)
				return
			}
			if msg.QoS == 1 {
				// Acknowledged immediately: the verification only needs the
				// payload, and leaving it unacknowledged would make the broker
				// redeliver.
				_ = c.send(pktPUBACK, 0, binary.BigEndian.AppendUint16(nil, packetID), 5*time.Second)
			}
			select {
			case c.messages <- msg:
			default: // a full buffer means nobody is reading; dropping is correct
			}
		case pktPUBACK:
			if len(body) >= 2 {
				select {
				case c.pubacks <- binary.BigEndian.Uint16(body):
				default:
				}
			}
		case pktSUBACK:
			if len(body) >= 2 {
				select {
				case c.subacks <- binary.BigEndian.Uint16(body):
				default:
				}
			}
		case pktPINGRESP:
		}
	}
}

func (c *Client) setReadErr(err error) {
	c.mu.Lock()
	if c.readErr == nil {
		c.readErr = err
	}
	c.mu.Unlock()
}

func (c *Client) ReadError() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.readErr
}

func (c *Client) packetID() uint16 {
	c.mu.Lock()
	defer c.mu.Unlock()
	id := c.nextID
	c.nextID++
	if c.nextID == 0 {
		c.nextID = 1
	}
	return id
}

// Subscribe registers a topic filter and waits for the broker's SUBACK.
func (c *Client) Subscribe(ctx context.Context, filter string, qos byte) error {
	id := c.packetID()

	var body []byte
	body = binary.BigEndian.AppendUint16(body, id)
	body = appendString(body, filter)
	body = append(body, qos)

	// SUBSCRIBE always carries flags 0x02 in the fixed header.
	if err := c.send(pktSUBSCRIBE, 0x02, body, 10*time.Second); err != nil {
		return err
	}

	select {
	case <-c.subacks:
		return nil
	case <-c.readDone:
		return c.closedError()
	case <-ctx.Done():
		return ctx.Err()
	case <-time.After(10 * time.Second):
		return fmt.Errorf("the broker did not acknowledge the subscription to %q", filter)
	}
}

// Publish sends an application message.
//
// At QoS 1 it waits for the broker's PUBACK, which is what makes a refusal
// observable: TrailMQ does not acknowledge a publish its policy denies, and
// may close the connection instead. Both outcomes return ErrRefused, so a
// caller proving enforcement gets a decision rather than a timeout.
func (c *Client) Publish(ctx context.Context, topic string, payload []byte, qos byte) error {
	var body []byte
	body = appendString(body, topic)

	var id uint16
	if qos > 0 {
		id = c.packetID()
		body = binary.BigEndian.AppendUint16(body, id)
	}
	body = append(body, payload...)

	flags := qos << 1
	if err := c.send(pktPUBLISH, flags, body, 10*time.Second); err != nil {
		return err
	}
	if qos == 0 {
		return nil
	}

	deadline := time.NewTimer(10 * time.Second)
	defer deadline.Stop()

	for {
		select {
		case got := <-c.pubacks:
			if got == id {
				return nil
			}
		case <-c.readDone:
			// The broker closed the connection rather than acknowledging.
			return ErrRefused
		case <-ctx.Done():
			return ctx.Err()
		case <-deadline.C:
			return ErrRefused
		}
	}
}

// Receive waits for the next incoming message.
func (c *Client) Receive(ctx context.Context, timeout time.Duration) (Message, error) {
	select {
	case msg := <-c.messages:
		return msg, nil
	case <-c.readDone:
		return Message{}, c.closedError()
	case <-ctx.Done():
		return Message{}, ctx.Err()
	case <-time.After(timeout):
		return Message{}, fmt.Errorf("no message arrived within %s", timeout)
	}
}

func (c *Client) closedError() error {
	if err := c.ReadError(); err != nil {
		return err
	}
	return ErrClosed
}

// Close sends DISCONNECT and closes the connection.
func (c *Client) Close() error {
	c.mu.Lock()
	if c.closed {
		c.mu.Unlock()
		return nil
	}
	c.closed = true
	c.mu.Unlock()

	_ = c.send(pktDISCONNECT, 0, nil, 2*time.Second)
	return c.conn.Close()
}

func (c *Client) send(kind, flags byte, body []byte, timeout time.Duration) error {
	if len(body) > maxRemainingSz {
		return errors.New("packet too large")
	}
	packet := append([]byte{kind<<4 | flags}, encodeRemainingLength(len(body))...)
	packet = append(packet, body...)

	if err := c.conn.SetWriteDeadline(time.Now().Add(timeout)); err != nil {
		return err
	}
	_, err := c.conn.Write(packet)
	return err
}

// --- wire format ------------------------------------------------------------

func appendString(dst []byte, s string) []byte {
	dst = binary.BigEndian.AppendUint16(dst, uint16(len(s)))
	return append(dst, s...)
}

func encodeRemainingLength(n int) []byte {
	var out []byte
	for {
		b := byte(n % 128)
		n /= 128
		if n > 0 {
			b |= 0x80
		}
		out = append(out, b)
		if n == 0 {
			return out
		}
	}
}

func readPacket(r io.Reader) (kind, flags byte, body []byte, err error) {
	var header [1]byte
	if _, err = io.ReadFull(r, header[:]); err != nil {
		return 0, 0, nil, err
	}
	kind = header[0] >> 4
	flags = header[0] & 0x0f

	length, err := readRemainingLength(r)
	if err != nil {
		return 0, 0, nil, err
	}
	if length > 0 {
		body = make([]byte, length)
		if _, err = io.ReadFull(r, body); err != nil {
			return 0, 0, nil, err
		}
	}
	return kind, flags, body, nil
}

func readRemainingLength(r io.Reader) (int, error) {
	var value, multiplier int
	var b [1]byte
	for i := 0; i < 4; i++ {
		if _, err := io.ReadFull(r, b[:]); err != nil {
			return 0, err
		}
		value += int(b[0]&127) << multiplier
		if b[0]&128 == 0 {
			return value, nil
		}
		multiplier += 7
	}
	return 0, errors.New("malformed remaining length")
}

func decodePublish(flags byte, body []byte) (Message, uint16, error) {
	qos := (flags >> 1) & 0x03
	if len(body) < 2 {
		return Message{}, 0, errors.New("truncated PUBLISH packet")
	}

	topicLen := int(binary.BigEndian.Uint16(body))
	if len(body) < 2+topicLen {
		return Message{}, 0, errors.New("truncated PUBLISH topic")
	}
	topic := string(body[2 : 2+topicLen])
	rest := body[2+topicLen:]

	var packetID uint16
	if qos > 0 {
		if len(rest) < 2 {
			return Message{}, 0, errors.New("truncated PUBLISH packet identifier")
		}
		packetID = binary.BigEndian.Uint16(rest)
		rest = rest[2:]
	}

	return Message{Topic: topic, Payload: rest, QoS: qos}, packetID, nil
}
