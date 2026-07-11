package handler

import (
	"errors"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/meta"
)

// statusFromK8sErr maps a Kubernetes API error to an HTTP status and a
// client-safe message. Forbidden is surfaced verbatim so the UI can show
// RBAC problems; everything else gets a sanitized message.
func statusFromK8sErr(err error) (int, string) {
	var nre *cluster.NotReadyError
	if errors.As(err, &nre) {
		return http.StatusServiceUnavailable, nre.Status.Message
	}
	switch {
	case apierrors.IsNotFound(err):
		return http.StatusNotFound, "resource not found"
	case apierrors.IsForbidden(err):
		return http.StatusForbidden, err.Error()
	case apierrors.IsConflict(err):
		return http.StatusConflict, "resource conflict, retry"
	case apierrors.IsInvalid(err), apierrors.IsBadRequest(err):
		return http.StatusUnprocessableEntity, err.Error()
	case apierrors.IsUnauthorized(err):
		return http.StatusUnauthorized, "unauthorized"
	case meta.IsNoMatchError(err):
		return http.StatusNotFound, err.Error()
	default:
		if statusErr, ok := err.(apierrors.APIStatus); ok {
			if msg := statusErr.Status().Message; msg != "" {
				return http.StatusInternalServerError, msg
			}
			if reason := string(statusErr.Status().Reason); reason != "" {
				return http.StatusInternalServerError, reason
			}
		}
		if msg := err.Error(); msg != "" {
			return http.StatusInternalServerError, msg
		}
		return http.StatusInternalServerError, "internal error"
	}
}
