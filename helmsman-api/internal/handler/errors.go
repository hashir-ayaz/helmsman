package handler

import (
	"errors"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
)

// statusFromK8sErr maps a Kubernetes API error to an HTTP status, optional
// typed code, and a client-safe message. Forbidden is surfaced verbatim so the
// UI can show RBAC problems; connectivity failures get friendly copy + codes.
func statusFromK8sErr(err error) (status int, code, msg string) {
	var nre *cluster.NotReadyError
	if errors.As(err, &nre) {
		return http.StatusServiceUnavailable, nre.Status.Code, nre.Status.Message
	}
	if c, message, ok := cluster.ClassifyConnectivity(err); ok {
		switch c {
		case cluster.CodeClusterTimeout:
			return http.StatusGatewayTimeout, c, message
		case cluster.CodeClusterAuth:
			// 502 rather than 401 so the Swift client keeps the typed code
			// (APIError.from maps 502/503/504 to .unavailable(code:)).
			return http.StatusBadGateway, c, message
		default:
			return http.StatusBadGateway, c, message
		}
	}
	switch {
	case apierrors.IsNotFound(err):
		return http.StatusNotFound, "", "resource not found"
	case apierrors.IsForbidden(err):
		return http.StatusForbidden, "", err.Error()
	case apierrors.IsConflict(err):
		return http.StatusConflict, "", "resource conflict, retry"
	case apierrors.IsInvalid(err), apierrors.IsBadRequest(err):
		return http.StatusUnprocessableEntity, "", err.Error()
	case apierrors.IsUnauthorized(err):
		return http.StatusUnauthorized, "", "unauthorized"
	case meta.IsNoMatchError(err):
		return http.StatusNotFound, "", err.Error()
	default:
		if statusErr, ok := err.(apierrors.APIStatus); ok {
			if m := statusErr.Status().Message; m != "" {
				return http.StatusInternalServerError, "", m
			}
			if reason := string(statusErr.Status().Reason); reason != "" {
				return http.StatusInternalServerError, "", reason
			}
		}
		if m := err.Error(); m != "" {
			return http.StatusInternalServerError, "", m
		}
		return http.StatusInternalServerError, "", "internal error"
	}
}
