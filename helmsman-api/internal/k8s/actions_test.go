package k8s

import (
	"context"
	"testing"

	"k8s.io/apimachinery/pkg/runtime/schema"
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
