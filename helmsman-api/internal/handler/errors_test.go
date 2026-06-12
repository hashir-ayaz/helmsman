package handler

import (
	"net/http"
	"testing"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

func TestStatusFromK8sErr(t *testing.T) {
	gr := schema.GroupResource{Resource: "pods"}
	cases := []struct {
		err  error
		want int
	}{
		{apierrors.NewNotFound(gr, "x"), http.StatusNotFound},
		{apierrors.NewForbidden(gr, "x", nil), http.StatusForbidden},
		{apierrors.NewConflict(gr, "x", nil), http.StatusConflict},
		{apierrors.NewInvalid(schema.GroupKind{Kind: "Pod"}, "x", nil), http.StatusUnprocessableEntity},
		{&apierrors.StatusError{ErrStatus: metav1.Status{}}, http.StatusInternalServerError},
	}
	for _, c := range cases {
		if got, _ := statusFromK8sErr(c.err); got != c.want {
			t.Errorf("status for %v = %d, want %d", c.err, got, c.want)
		}
	}
}
