package handler

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	"k8s.io/apimachinery/pkg/api/meta/testrestmapper"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/dynamic"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/kubernetes/scheme"
)

type fakeProvider struct {
	bundle *cluster.ClientBundle
}

func (f *fakeProvider) Contexts() []cluster.ContextInfo {
	return []cluster.ContextInfo{{Name: "dev", Cluster: "c", Namespace: "default", IsCurrent: true}}
}
func (f *fakeProvider) Current() string                              { return "dev" }
func (f *fakeProvider) Bundle(string) (*cluster.ClientBundle, error) { return f.bundle, nil }

func newFakeProvider(objs ...runtime.Object) *fakeProvider {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), objs...)
	return &fakeProvider{bundle: &cluster.ClientBundle{
		Dynamic: dyn,
		Mapper:  testrestmapper.TestOnlyStaticRESTMapper(scheme.Scheme),
	}}
}

var _ dynamic.Interface = (*dynamicfake.FakeDynamicClient)(nil)

func TestContextsEndpoint(t *testing.T) {
	h := New(newFakeProvider())
	req := httptest.NewRequest(http.MethodGet, "/api/v1/contexts", nil)
	rec := httptest.NewRecorder()
	h.Contexts.List(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d", rec.Code)
	}
	var resp APIResponse
	json.Unmarshal(rec.Body.Bytes(), &resp)
	if resp.Data == nil {
		t.Error("expected contexts in data")
	}
}

func TestResourceGet(t *testing.T) {
	cm := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "ConfigMap",
		"metadata": map[string]any{"name": "cm-1", "namespace": "default"},
	}}
	h := New(newFakeProvider(cm))

	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("resource", "configmaps")
	req.SetPathValue("name", "cm-1")
	rec := httptest.NewRecorder()
	h.Resources.Get(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
}
