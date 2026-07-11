package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

type statusProvider struct {
	status cluster.Status
}

func (s *statusProvider) Contexts() []cluster.ContextInfo { return nil }
func (s *statusProvider) Current() string                 { return "" }
func (s *statusProvider) Bundle(string) (*cluster.ClientBundle, error) {
	return nil, &cluster.NotReadyError{Status: s.status}
}
func (s *statusProvider) Status() cluster.Status { return s.status }

func TestStatusEndpointReady(t *testing.T) {
	h := New(newFakeProvider())
	req := httptest.NewRequest(http.MethodGet, "/api/v1/status", nil)
	rec := httptest.NewRecorder()
	h.Status.Get(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d", rec.Code)
	}
	var resp APIResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	data, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("data type = %T", resp.Data)
	}
	if ready, _ := data["ready"].(bool); !ready {
		t.Errorf("ready = %v, want true", data["ready"])
	}
}

func TestStatusEndpointNotReady(t *testing.T) {
	p := &statusProvider{
		status: cluster.Status{
			Ready:   false,
			Code:    "kubeconfig_not_found",
			Message: "No kubeconfig found at /tmp/missing.",
		},
	}
	h := New(p)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/status", nil)
	rec := httptest.NewRecorder()
	h.Status.Get(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d", rec.Code)
	}
	var resp APIResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatal(err)
	}
	data := resp.Data.(map[string]any)
	if ready, _ := data["ready"].(bool); ready {
		t.Error("expected not ready")
	}
	if data["code"] != "kubeconfig_not_found" {
		t.Errorf("code = %v", data["code"])
	}
}

func TestContextsEndpointNotReady(t *testing.T) {
	p := &statusProvider{
		status: cluster.Status{
			Ready:   false,
			Code:    "kubeconfig_not_found",
			Message: "No kubeconfig found.",
		},
	}
	h := New(p)
	req := httptest.NewRequest(http.MethodGet, "/api/v1/contexts", nil)
	rec := httptest.NewRecorder()
	h.Contexts.List(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("code = %d, want 503", rec.Code)
	}
}
