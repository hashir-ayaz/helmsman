package k8s

import (
	"context"
	"errors"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	k8stesting "k8s.io/client-go/testing"
)

var pvcGVR = schema.GroupVersionResource{Version: "v1", Resource: "persistentvolumeclaims"}

func newPVC(name, storage string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1",
		"kind":       "PersistentVolumeClaim",
		"metadata": map[string]any{
			"name":      name,
			"namespace": "default",
		},
		"spec": map[string]any{
			"resources": map[string]any{
				"requests": map[string]any{
					"storage": storage,
				},
			},
		},
	}}
}

func TestResizePVCPatchShape(t *testing.T) {
	got := string(resizePVCPatch("50Gi"))
	want := `{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}`
	if got != want {
		t.Fatalf("resizePVCPatch = %s, want %s", got, want)
	}
}

func TestResizePVC_sendsPatch(t *testing.T) {
	dyn := fakeDyn(newPVC("data", "42Gi"))
	var got []byte
	dyn.PrependReactor("patch", "*", func(action k8stesting.Action) (bool, runtime.Object, error) {
		got = action.(k8stesting.PatchAction).GetPatch()
		return true, newPVC("data", "50Gi"), nil
	})

	ref := ResourceRef{GVR: pvcGVR, Namespaced: true}
	if err := ResizePVC(context.Background(), dyn, ref, "default", "data", "50Gi"); err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"spec":{"resources":{"requests":{"storage":"50Gi"}}}}` {
		t.Errorf("patch = %s", got)
	}
}

func TestResizePVC_rejectsShrink(t *testing.T) {
	dyn := fakeDyn(newPVC("data", "42Gi"))
	ref := ResourceRef{GVR: pvcGVR, Namespaced: true}
	err := ResizePVC(context.Background(), dyn, ref, "default", "data", "10Gi")
	if err == nil {
		t.Fatal("expected shrink error")
	}
	if !errors.Is(err, ErrPVCStorageShrink) {
		t.Fatalf("expected ErrPVCStorageShrink, got %v", err)
	}
}
