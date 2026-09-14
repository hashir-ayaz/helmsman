package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

// recordingProvider captures the contextName passed to Probe so tests can
// assert on how the handler resolved the {ctx} path segment.
type recordingProvider struct {
	*fakeProvider
	contexts []cluster.ContextInfo
	probed   []string
}

func newRecordingProvider(names ...string) *recordingProvider {
	infos := make([]cluster.ContextInfo, 0, len(names))
	for _, n := range names {
		infos = append(infos, cluster.ContextInfo{Name: n, Cluster: "c"})
	}
	return &recordingProvider{fakeProvider: newFakeProvider(), contexts: infos}
}

func (p *recordingProvider) Contexts() []cluster.ContextInfo { return p.contexts }
func (p *recordingProvider) Probe(_ context.Context, contextName string) cluster.Status {
	p.probed = append(p.probed, contextName)
	return cluster.Status{Ready: true, Code: "ready"}
}

func decodeContextStatus(t *testing.T, rec *httptest.ResponseRecorder) APIResponse {
	t.Helper()
	var resp APIResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode body %q: %v", rec.Body.String(), err)
	}
	return resp
}

func TestContextStatusReady(t *testing.T) {
	h := New(newFakeProvider())
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	rec := httptest.NewRecorder()
	h.Contexts.Status(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
	resp := decodeContextStatus(t, rec)
	data, ok := resp.Data.(map[string]any)
	if !ok {
		t.Fatalf("data type = %T", resp.Data)
	}
	if ready, _ := data["ready"].(bool); !ready {
		t.Errorf("ready = %v, want true", data["ready"])
	}
}

func TestContextStatusCurrentSentinel(t *testing.T) {
	p := newRecordingProvider("dev")
	h := New(p)
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", currentSentinel)
	rec := httptest.NewRecorder()
	h.Contexts.Status(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
	if len(p.probed) != 1 {
		t.Fatalf("Probe called %d times, want 1", len(p.probed))
	}
	if p.probed[0] != "" {
		t.Errorf("Probe contextName = %q, want empty (current)", p.probed[0])
	}
}

func TestContextStatusUnknownContext(t *testing.T) {
	p := newRecordingProvider("dev")
	h := New(p)
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "bogus")
	rec := httptest.NewRecorder()
	h.Contexts.Status(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("code = %d, want 404, body = %s", rec.Code, rec.Body.String())
	}
	resp := decodeContextStatus(t, rec)
	if resp.Code != "context_not_found" {
		t.Errorf("envelope code = %q, want context_not_found", resp.Code)
	}
	if !strings.Contains(resp.Error, "bogus") {
		t.Errorf("error = %q, want it to name the missing context", resp.Error)
	}
	if len(p.probed) != 0 {
		t.Errorf("Probe called with %v, want no calls for unknown context", p.probed)
	}
}

func TestContextStatusKubeconfigNotReady(t *testing.T) {
	p := &statusProvider{
		status: cluster.Status{
			Ready:   false,
			Code:    "kubeconfig_not_found",
			Message: "No kubeconfig found at /tmp/missing.",
		},
	}
	h := New(p)
	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	rec := httptest.NewRecorder()
	h.Contexts.Status(rec, req)

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("code = %d, want 503, body = %s", rec.Code, rec.Body.String())
	}
	resp := decodeContextStatus(t, rec)
	if resp.Code != "kubeconfig_not_found" {
		t.Errorf("envelope code = %q, want kubeconfig_not_found", resp.Code)
	}
}

// TestContextStatusEscapedSlashRoutes pins the Go 1.22 ServeMux contract:
// an escaped slash (%2F) inside a {ctx} wildcard stays in one segment and
// PathValue returns it unescaped, so EKS ARN context names route correctly.
func TestContextStatusEscapedSlashRoutes(t *testing.T) {
	const arn = "arn:aws:eks:us-east-2:1:cluster/prod"
	p := newRecordingProvider("dev", arn)
	h := New(p)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/status", h.Contexts.Status)

	req := httptest.NewRequest(http.MethodGet,
		"/api/v1/contexts/arn%3Aaws%3Aeks%3Aus-east-2%3A1%3Acluster%2Fprod/status", nil)
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, want 200, body = %s", rec.Code, rec.Body.String())
	}
	if len(p.probed) != 1 {
		t.Fatalf("Probe called %d times, want 1", len(p.probed))
	}
	if p.probed[0] != arn {
		t.Errorf("Probe contextName = %q, want %q", p.probed[0], arn)
	}
}
