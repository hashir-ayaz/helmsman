package cluster

import (
	"context"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"testing"
)

func TestClassifyConnectivityTimeout(t *testing.T) {
	code, msg, ok := ClassifyConnectivity(context.DeadlineExceeded)
	if !ok || code != CodeClusterTimeout {
		t.Fatalf("got ok=%v code=%q, want timeout", ok, code)
	}
	if msg == "" {
		t.Fatal("expected message")
	}

	code, _, ok = ClassifyConnectivity(fmt.Errorf("Get https://x: %w", &timeoutError{}))
	if !ok || code != CodeClusterTimeout {
		t.Fatalf("net.Error timeout: ok=%v code=%q", ok, code)
	}

	code, _, ok = ClassifyConnectivity(errors.New(`Get "https://x": dial tcp: i/o timeout`))
	if !ok || code != CodeClusterTimeout {
		t.Fatalf("i/o timeout string: ok=%v code=%q", ok, code)
	}
}

func TestClassifyConnectivityUnreachable(t *testing.T) {
	cases := []error{
		errors.New(`Get "https://127.0.0.1:6443/": dial tcp 127.0.0.1:6443: connection refused`),
		errors.New("dial tcp: lookup api.example: no such host"),
		errors.New("dial tcp: network is unreachable"),
		&net.OpError{Op: "dial", Err: errors.New("connect: connection refused")},
	}
	for _, err := range cases {
		code, msg, ok := ClassifyConnectivity(err)
		if !ok || code != CodeClusterUnreachable {
			t.Errorf("%v → ok=%v code=%q, want unreachable", err, ok, code)
		}
		if msg == "" {
			t.Errorf("%v: empty message", err)
		}
	}
}

func TestClassifyConnectivityTLS(t *testing.T) {
	err := fmt.Errorf("Get https://x: %w", x509.UnknownAuthorityError{})
	code, msg, ok := ClassifyConnectivity(err)
	if !ok || code != CodeClusterUnreachable {
		t.Fatalf("got ok=%v code=%q", ok, code)
	}
	if msg != msgClusterTLS {
		t.Errorf("msg = %q, want TLS message", msg)
	}
}

func TestClassifyConnectivityNonConnectivity(t *testing.T) {
	_, _, ok := ClassifyConnectivity(errors.New("pods is forbidden"))
	if ok {
		t.Fatal("expected not connectivity")
	}
	_, _, ok = ClassifyConnectivity(nil)
	if ok {
		t.Fatal("nil should not classify")
	}
}

type timeoutError struct{}

func (timeoutError) Error() string   { return "i/o timeout" }
func (timeoutError) Timeout() bool   { return true }
func (timeoutError) Temporary() bool { return true }
