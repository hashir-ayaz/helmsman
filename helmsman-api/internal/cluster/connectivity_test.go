package cluster

import (
	"context"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"testing"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime/schema"
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

func TestClassifyConnectivityAuth(t *testing.T) {
	cases := []error{
		apierrors.NewUnauthorized("token expired"),
		fmt.Errorf("wrapped: %w", apierrors.NewUnauthorized("x")),
		errors.New(`Get "https://h/version": getting credentials: exec: executable aws failed with exit code 255`),
		errors.New("exec: executable gke-gcloud-auth-plugin not found"),
		errors.New(`no Auth Provider found for name "gcp"`),
	}
	for _, err := range cases {
		code, msg, ok := ClassifyConnectivity(err)
		if !ok || code != CodeClusterAuth {
			t.Errorf("%v → ok=%v code=%q, want auth", err, ok, code)
		}
		if msg == "" {
			t.Errorf("%v: empty message", err)
		}
	}

	// Dial failures must keep their unreachable classification.
	code, _, ok := ClassifyConnectivity(errors.New("dial tcp 127.0.0.1:6443: connect: connection refused"))
	if !ok || code != CodeClusterUnreachable {
		t.Errorf("connection refused → ok=%v code=%q, want unreachable", ok, code)
	}

	// RBAC forbidden is first-class in the app and must stay unclassified.
	notAuth := []error{
		errors.New("pods is forbidden"),
		apierrors.NewForbidden(schema.GroupResource{Resource: "pods"}, "x", errors.New("rbac")),
	}
	for _, err := range notAuth {
		code, _, ok := ClassifyConnectivity(err)
		if ok || code == CodeClusterAuth {
			t.Errorf("%v → ok=%v code=%q, want unclassified", err, ok, code)
		}
	}
}

func TestStatusFromConnectivityAuth(t *testing.T) {
	err := errors.New(`Get "https://h/version": getting credentials: exec: executable aws failed with exit code 255`)
	st := StatusFromConnectivity(err)
	if st.Ready {
		t.Fatal("expected Ready=false")
	}
	if st.Code != CodeClusterAuth {
		t.Errorf("Code = %q, want %q", st.Code, CodeClusterAuth)
	}
	if st.Message == "" {
		t.Error("expected message")
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
