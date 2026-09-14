package cluster

import (
	"context"
	"crypto/x509"
	"errors"
	"net"
	"os"
	"strings"
	"syscall"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
)

// Typed connectivity / readiness codes returned to the frontend.
const (
	CodeClusterUnreachable = "cluster_unreachable"
	CodeClusterTimeout     = "cluster_timeout"
	CodeClusterAuth        = "cluster_auth"
)

const (
	msgClusterUnreachable = "Could not reach the cluster API server. Check that the cluster is running."
	msgClusterTimeout     = "The cluster API server did not respond in time."
	msgClusterTLS         = "Could not establish a secure connection to the cluster API server."
	msgClusterAuth        = "Helmsman could not authenticate to this cluster. Your credentials may have expired or the auth plugin is missing."
)

// ClassifyConnectivity maps dial/timeout/TLS transport errors to a typed code
// and a user-facing message. ok is false when err is not a connectivity failure.
func ClassifyConnectivity(err error) (code, message string, ok bool) {
	if err == nil {
		return "", "", false
	}

	if errors.Is(err, context.DeadlineExceeded) || errors.Is(err, os.ErrDeadlineExceeded) {
		return CodeClusterTimeout, msgClusterTimeout, true
	}

	var netErr net.Error
	if errors.As(err, &netErr) && netErr.Timeout() {
		return CodeClusterTimeout, msgClusterTimeout, true
	}

	lower := strings.ToLower(err.Error())
	if strings.Contains(lower, "i/o timeout") ||
		strings.Contains(lower, "deadline exceeded") ||
		strings.Contains(lower, "client.timeout exceeded") {
		return CodeClusterTimeout, msgClusterTimeout, true
	}

	var (
		unknownAuth *x509.UnknownAuthorityError
		hostnameErr *x509.HostnameError
		certInvalid *x509.CertificateInvalidError
	)
	if errors.As(err, &unknownAuth) ||
		errors.As(err, &hostnameErr) ||
		errors.As(err, &certInvalid) ||
		strings.Contains(lower, "tls:") ||
		strings.Contains(lower, "x509:") {
		return CodeClusterUnreachable, msgClusterTLS, true
	}

	if errors.Is(err, syscall.ECONNREFUSED) ||
		errors.Is(err, syscall.EHOSTUNREACH) ||
		errors.Is(err, syscall.ENETUNREACH) ||
		strings.Contains(lower, "connection refused") ||
		strings.Contains(lower, "no such host") ||
		strings.Contains(lower, "network is unreachable") ||
		strings.Contains(lower, "no route to host") ||
		strings.Contains(lower, "connection reset") {
		return CodeClusterUnreachable, msgClusterUnreachable, true
	}

	// Credential failures. Exec-plugin errors (aws eks get-token,
	// gke-gcloud-auth-plugin, …) reach us as string-only errors because
	// client-go formats them with %v, not %w, so they must be matched on text.
	// Forbidden (RBAC 403) is deliberately excluded — the app surfaces it as-is.
	if apierrors.IsUnauthorized(err) ||
		strings.Contains(lower, "getting credentials:") ||
		strings.Contains(lower, "exec: executable") ||
		strings.Contains(lower, "exec plugin") ||
		strings.Contains(lower, "no auth provider found") {
		return CodeClusterAuth, msgClusterAuth, true
	}

	var opErr *net.OpError
	if errors.As(err, &opErr) {
		return CodeClusterUnreachable, msgClusterUnreachable, true
	}

	return "", "", false
}

// StatusFromConnectivity builds a not-ready Status for a connectivity error.
// Falls back to cluster_unreachable when the error is unclassified.
func StatusFromConnectivity(err error) Status {
	if code, message, ok := ClassifyConnectivity(err); ok {
		return Status{Ready: false, Code: code, Message: message}
	}
	return Status{
		Ready:   false,
		Code:    CodeClusterUnreachable,
		Message: msgClusterUnreachable,
	}
}
