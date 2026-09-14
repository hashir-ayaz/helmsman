package handler

import (
	"context"
	"errors"
	"net/http"
	"testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

func TestStatusFromK8sErr(t *testing.T) {
	gr := schema.GroupResource{Resource: "pods"}
	cases := []struct {
		err        error
		wantStatus int
		wantCode   string
	}{
		{apierrors.NewNotFound(gr, "x"), http.StatusNotFound, ""},
		{apierrors.NewForbidden(gr, "x", nil), http.StatusForbidden, ""},
		{apierrors.NewConflict(gr, "x", nil), http.StatusConflict, ""},
		{apierrors.NewInvalid(schema.GroupKind{Kind: "Pod"}, "x", nil), http.StatusUnprocessableEntity, ""},
		{&apierrors.StatusError{ErrStatus: metav1.Status{}}, http.StatusInternalServerError, ""},
		{
			&cluster.NotReadyError{Status: cluster.Status{
				Code: "kubeconfig_not_found", Message: "missing",
			}},
			http.StatusServiceUnavailable,
			"kubeconfig_not_found",
		},
		{
			errors.New(`Get "https://127.0.0.1:6443/": dial tcp 127.0.0.1:6443: connection refused`),
			http.StatusBadGateway,
			cluster.CodeClusterUnreachable,
		},
		{
			context.DeadlineExceeded,
			http.StatusGatewayTimeout,
			cluster.CodeClusterTimeout,
		},
		{
			errors.New(`Get "https://h/version": getting credentials: exec: executable aws failed with exit code 255`),
			http.StatusBadGateway,
			cluster.CodeClusterAuth,
		},
	}
	for _, c := range cases {
		gotStatus, gotCode, _ := statusFromK8sErr(c.err)
		if gotStatus != c.wantStatus || gotCode != c.wantCode {
			t.Errorf("statusFromK8sErr(%v) = (%d, %q), want (%d, %q)",
				c.err, gotStatus, gotCode, c.wantStatus, c.wantCode)
		}
	}
}

func TestStatusFromK8sErrStatusMessage(t *testing.T) {
	err := &apierrors.StatusError{
		ErrStatus: metav1.Status{
			Message: "apply failed: field is immutable",
			Reason:  metav1.StatusReasonInternalError,
		},
	}
	status, code, msg := statusFromK8sErr(err)
	if status != http.StatusInternalServerError {
		t.Errorf("status = %d, want 500", status)
	}
	if code != "" {
		t.Errorf("code = %q, want empty", code)
	}
	if msg != "apply failed: field is immutable" {
		t.Errorf("msg = %q", msg)
	}
}

func TestStatusFromK8sErrAuthPluginIsTyped(t *testing.T) {
	err := errors.New(`Get "https://h/version": getting credentials: exec: executable aws failed with exit code 255`)
	status, code, msg := statusFromK8sErr(err)
	if status != http.StatusBadGateway {
		t.Errorf("status = %d, want 502", status)
	}
	if code != cluster.CodeClusterAuth {
		t.Errorf("code = %q, want %q", code, cluster.CodeClusterAuth)
	}
	if msg == "" || msg == err.Error() {
		t.Errorf("msg = %q, want friendly non-empty message", msg)
	}
}

func TestStatusFromK8sErrForbiddenStaysRBAC(t *testing.T) {
	err := apierrors.NewForbidden(schema.GroupResource{Resource: "pods"}, "x", errors.New("rbac"))
	status, code, _ := statusFromK8sErr(err)
	if status != http.StatusForbidden {
		t.Errorf("status = %d, want 403", status)
	}
	if code != "" {
		t.Errorf("code = %q, want empty", code)
	}
}

func TestStatusFromK8sErrConnectivityMessageIsFriendly(t *testing.T) {
	err := errors.New(`Get "https://127.0.0.1:6443/api/v1/pods": dial tcp 127.0.0.1:6443: connection refused`)
	_, code, msg := statusFromK8sErr(err)
	if code != cluster.CodeClusterUnreachable {
		t.Fatalf("code = %q", code)
	}
	if msg == err.Error() {
		t.Fatal("expected friendly message, got raw dial error")
	}
}
