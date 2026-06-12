package k8s

import (
	"context"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	k8stesting "k8s.io/client-go/testing"
)

var deployGVR = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "deployments"}

func TestRestartPatchShape(t *testing.T) {
	// Restart must produce a strategic-merge patch with the restartedAt annotation.
	patch := restartPatch("2026-06-10T00:00:00Z")
	want := `{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":"2026-06-10T00:00:00Z"}}}}}`
	if string(patch) != want {
		t.Errorf("restartPatch = %s, want %s", patch, want)
	}
}

func TestScalePatchShape(t *testing.T) {
	if got := string(scalePatch(3)); got != `{"spec":{"replicas":3}}` {
		t.Errorf("scalePatch = %s", got)
	}
}

func TestScaleCallsSubresource(t *testing.T) {
	dyn := fakeDyn()
	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	// Just assert it does not panic / returns a clean error path on missing object.
	if err := Scale(context.Background(), dyn, ref, "default", "missing", 3); err == nil {
		t.Error("expected error scaling missing deployment")
	}
}

func TestSetSuspend_sendsPatch(t *testing.T) {
	dyn := fakeDyn()
	var got []byte
	dyn.PrependReactor("patch", "*", func(action k8stesting.Action) (bool, runtime.Object, error) {
		got = action.(k8stesting.PatchAction).GetPatch()
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "batch/v1", "kind": "CronJob",
			"metadata": map[string]any{"name": "myjob", "namespace": "default"},
		}}, nil
	})

	ref := ResourceRef{
		GVR:        schema.GroupVersionResource{Group: "batch", Version: "v1", Resource: "cronjobs"},
		Namespaced: true,
	}
	if err := SetSuspend(context.Background(), dyn, ref, "default", "myjob", true); err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"spec":{"suspend":true}}` {
		t.Errorf("suspend patch = %s", got)
	}
}

func TestSetSuspend_resume(t *testing.T) {
	dyn := fakeDyn()
	var got []byte
	dyn.PrependReactor("patch", "*", func(action k8stesting.Action) (bool, runtime.Object, error) {
		got = action.(k8stesting.PatchAction).GetPatch()
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "batch/v1", "kind": "CronJob",
			"metadata": map[string]any{"name": "myjob", "namespace": "default"},
		}}, nil
	})

	ref := ResourceRef{
		GVR:        schema.GroupVersionResource{Group: "batch", Version: "v1", Resource: "cronjobs"},
		Namespaced: true,
	}
	if err := SetSuspend(context.Background(), dyn, ref, "default", "myjob", false); err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"spec":{"suspend":false}}` {
		t.Errorf("resume patch = %s", got)
	}
}
