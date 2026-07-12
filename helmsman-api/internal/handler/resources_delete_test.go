package handler

import (
	"net/http/httptest"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestParseDeleteOptions_defaults(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1", nil)
	opts, err := parseDeleteOptions(r)
	if err != nil {
		t.Fatal(err)
	}
	if opts.GracePeriodSeconds != nil || opts.PropagationPolicy != nil {
		t.Fatalf("expected empty options, got %+v", opts)
	}
}

func TestParseDeleteOptions_gracePeriodZero(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?gracePeriodSeconds=0", nil)
	opts, err := parseDeleteOptions(r)
	if err != nil {
		t.Fatal(err)
	}
	if opts.GracePeriodSeconds == nil || *opts.GracePeriodSeconds != 0 {
		t.Fatalf("gracePeriodSeconds = %v, want 0", opts.GracePeriodSeconds)
	}
}

func TestParseDeleteOptions_propagationPolicy(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?propagationPolicy=Foreground", nil)
	opts, err := parseDeleteOptions(r)
	if err != nil {
		t.Fatal(err)
	}
	if opts.PropagationPolicy == nil || *opts.PropagationPolicy != metav1.DeletePropagationForeground {
		t.Fatalf("propagationPolicy = %v, want Foreground", opts.PropagationPolicy)
	}
}

func TestParseDeleteOptions_invalidGracePeriod(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?gracePeriodSeconds=abc", nil)
	_, err := parseDeleteOptions(r)
	if err == nil {
		t.Fatal("expected error for invalid gracePeriodSeconds")
	}
}

func TestParseDeleteOptions_propagationPolicyBackground(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?propagationPolicy=Background", nil)
	opts, err := parseDeleteOptions(r)
	if err != nil {
		t.Fatal(err)
	}
	if opts.PropagationPolicy == nil || *opts.PropagationPolicy != metav1.DeletePropagationBackground {
		t.Fatalf("propagationPolicy = %v, want Background", opts.PropagationPolicy)
	}
}

func TestParseDeleteOptions_propagationPolicyOrphan(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?propagationPolicy=Orphan", nil)
	opts, err := parseDeleteOptions(r)
	if err != nil {
		t.Fatal(err)
	}
	if opts.PropagationPolicy == nil || *opts.PropagationPolicy != metav1.DeletePropagationOrphan {
		t.Fatalf("propagationPolicy = %v, want Orphan", opts.PropagationPolicy)
	}
}

func TestParseDeleteOptions_combined(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?gracePeriodSeconds=0&propagationPolicy=Foreground", nil)
	opts, err := parseDeleteOptions(r)
	if err != nil {
		t.Fatal(err)
	}
	if opts.GracePeriodSeconds == nil || *opts.GracePeriodSeconds != 0 {
		t.Fatalf("gracePeriodSeconds = %v, want 0", opts.GracePeriodSeconds)
	}
	if opts.PropagationPolicy == nil || *opts.PropagationPolicy != metav1.DeletePropagationForeground {
		t.Fatalf("propagationPolicy = %v, want Foreground", opts.PropagationPolicy)
	}
}

func TestParseDeleteOptions_invalidPropagationPolicy(t *testing.T) {
	r := httptest.NewRequest("DELETE", "/resources/cm-1?propagationPolicy=Invalid", nil)
	_, err := parseDeleteOptions(r)
	if err == nil {
		t.Fatal("expected error for invalid propagationPolicy")
	}
}
