package handler

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	"k8s.io/apimachinery/pkg/api/meta/testrestmapper"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	watchpkg "k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/dynamic"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	"k8s.io/client-go/kubernetes/scheme"
	k8stesting "k8s.io/client-go/testing"
)

type fakeProvider struct {
	bundle *cluster.ClientBundle
}

func (f *fakeProvider) Contexts() []cluster.ContextInfo {
	return []cluster.ContextInfo{{Name: "dev", Cluster: "c", Namespace: "default", IsCurrent: true}}
}
func (f *fakeProvider) Current() string                              { return "dev" }
func (f *fakeProvider) Bundle(string) (*cluster.ClientBundle, error) { return f.bundle, nil }
func (f *fakeProvider) Status() cluster.Status {
	return cluster.Status{Ready: true, Code: "ready"}
}

func newFakeProvider(objs ...runtime.Object) *fakeProvider {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), objs...)
	return &fakeProvider{bundle: &cluster.ClientBundle{
		Dynamic: dyn,
		Mapper:  testrestmapper.TestOnlyStaticRESTMapper(scheme.Scheme),
	}}
}

// newFakeProviderWithRS creates a fake provider that can also list ReplicaSets,
// which is required by RolloutHistory and RolloutUndo.
func newFakeProviderWithRS(objs ...runtime.Object) *fakeProvider {
	gvrToListKind := map[schema.GroupVersionResource]string{
		{Group: "apps", Version: "v1", Resource: "deployments"}:  "DeploymentList",
		{Group: "apps", Version: "v1", Resource: "replicasets"}: "ReplicaSetList",
	}
	dyn := dynamicfake.NewSimpleDynamicClientWithCustomListKinds(runtime.NewScheme(), gvrToListKind, objs...)
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

func TestWatchEndpoint_SSEHeaders(t *testing.T) {
	h := New(newFakeProvider())
	fakeWatcher := watchpkg.NewFake()
	fakeDynClient := h.Watch.provider.(*fakeProvider).bundle.Dynamic.(*dynamicfake.FakeDynamicClient)
	fakeDynClient.PrependWatchReactor("*", func(_ k8stesting.Action) (bool, watchpkg.Interface, error) {
		return true, fakeWatcher, nil
	})

	// Cancel the context before the handler runs. The Watch goroutine sees
	// ctx.Done() immediately and closes the channel, so the handler returns
	// synchronously without needing any sleep-based synchronization.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	req := httptest.NewRequest(http.MethodGet, "/x", nil).WithContext(ctx)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("resource", "configmaps")
	rec := httptest.NewRecorder()

	h.Watch.Stream(rec, req)

	if ct := rec.Header().Get("Content-Type"); ct != "text/event-stream" {
		t.Errorf("Content-Type = %q, want text/event-stream", ct)
	}
	if rec.Code != http.StatusOK {
		t.Errorf("status = %d, want 200", rec.Code)
	}
}

func TestScaleHandler_usesWorkloadPathParam(t *testing.T) {
	h := New(newFakeProvider())
	fakeDynClient := h.Actions.provider.(*fakeProvider).bundle.Dynamic.(*dynamicfake.FakeDynamicClient)

	var capturedResource string
	fakeDynClient.PrependReactor("patch", "*", func(action k8stesting.Action) (bool, runtime.Object, error) {
		capturedResource = action.GetResource().Resource
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "apps/v1", "kind": "StatefulSet",
			"metadata": map[string]any{"name": "my-sts", "namespace": "default"},
		}}, nil
	})

	req := httptest.NewRequest(http.MethodPost, "/x", strings.NewReader(`{"replicas":2}`))
	req.Header.Set("Content-Type", "application/json")
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("workload", "statefulsets")
	req.SetPathValue("name", "my-sts")
	rec := httptest.NewRecorder()
	h.Actions.Scale(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
	if capturedResource != "statefulsets" {
		t.Errorf("Scale used resource %q, want statefulsets", capturedResource)
	}
}

func TestRolloutHistoryEndpoint(t *testing.T) {
	deploy := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "Deployment",
		"metadata": map[string]any{
			"name": "my-deploy", "namespace": "default", "uid": "deploy-uid",
			"annotations": map[string]any{"deployment.kubernetes.io/revision": "1"},
		},
	}}
	h := New(newFakeProviderWithRS(deploy))

	req := httptest.NewRequest(http.MethodGet, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("workload", "deployments")
	req.SetPathValue("name", "my-deploy")
	rec := httptest.NewRecorder()
	h.Rollout.History(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
}

func TestRolloutUndoEndpoint_missingRevision(t *testing.T) {
	deploy := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "Deployment",
		"metadata": map[string]any{
			"name": "my-deploy", "namespace": "default", "uid": "deploy-uid",
			"annotations": map[string]any{"deployment.kubernetes.io/revision": "1"},
		},
	}}
	// No replicasets seeded → revision 5 not found → expect non-200.
	h := New(newFakeProviderWithRS(deploy))

	req := httptest.NewRequest(http.MethodPost, "/x", strings.NewReader(`{"toRevision":5}`))
	req.Header.Set("Content-Type", "application/json")
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("workload", "deployments")
	req.SetPathValue("name", "my-deploy")
	rec := httptest.NewRecorder()
	h.Rollout.Undo(rec, req)

	if rec.Code == http.StatusOK {
		t.Errorf("expected non-200 for missing revision, got 200")
	}
}

func TestRolloutPauseEndpoint(t *testing.T) {
	h := New(newFakeProvider())
	fakeDynClient := h.Rollout.provider.(*fakeProvider).bundle.Dynamic.(*dynamicfake.FakeDynamicClient)
	fakeDynClient.PrependReactor("patch", "deployments", func(action k8stesting.Action) (bool, runtime.Object, error) {
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "apps/v1", "kind": "Deployment",
			"metadata": map[string]any{"name": "my-deploy", "namespace": "default"},
		}}, nil
	})

	req := httptest.NewRequest(http.MethodPost, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("workload", "deployments")
	req.SetPathValue("name", "my-deploy")
	rec := httptest.NewRecorder()
	h.Rollout.Pause(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
}

func TestSuspendEndpoint(t *testing.T) {
	h := New(newFakeProvider())
	fakeDynClient := h.Actions.provider.(*fakeProvider).bundle.Dynamic.(*dynamicfake.FakeDynamicClient)
	fakeDynClient.PrependReactor("patch", "*", func(action k8stesting.Action) (bool, runtime.Object, error) {
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "batch/v1", "kind": "CronJob",
			"metadata": map[string]any{"name": "my-cron", "namespace": "default"},
		}}, nil
	})

	req := httptest.NewRequest(http.MethodPost, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("workload", "cronjobs")
	req.SetPathValue("name", "my-cron")
	rec := httptest.NewRecorder()
	h.Actions.Suspend(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
}

func TestResumeEndpoint(t *testing.T) {
	h := New(newFakeProvider())
	fakeDynClient := h.Actions.provider.(*fakeProvider).bundle.Dynamic.(*dynamicfake.FakeDynamicClient)
	fakeDynClient.PrependReactor("patch", "*", func(action k8stesting.Action) (bool, runtime.Object, error) {
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "batch/v1", "kind": "CronJob",
			"metadata": map[string]any{"name": "my-cron", "namespace": "default"},
		}}, nil
	})

	req := httptest.NewRequest(http.MethodPost, "/x", nil)
	req.SetPathValue("ctx", "dev")
	req.SetPathValue("ns", "default")
	req.SetPathValue("workload", "cronjobs")
	req.SetPathValue("name", "my-cron")
	rec := httptest.NewRecorder()
	h.Actions.Resume(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("code = %d, body = %s", rec.Code, rec.Body.String())
	}
}
