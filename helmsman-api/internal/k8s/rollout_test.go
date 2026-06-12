package k8s

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	k8stesting "k8s.io/client-go/testing"
)

func testDeploy(name, uid, currentRevision string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "Deployment",
		"metadata": map[string]any{
			"name": name, "namespace": "default", "uid": uid,
			"annotations": map[string]any{
				"deployment.kubernetes.io/revision": currentRevision,
			},
		},
	}}
}

func testRS(name, ownerUID, revision, image string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "ReplicaSet",
		"metadata": map[string]any{
			"name": name, "namespace": "default",
			"creationTimestamp": "2026-01-01T00:00:00Z",
			"annotations": map[string]any{
				"deployment.kubernetes.io/revision": revision,
			},
			"ownerReferences": []any{
				map[string]any{
					"apiVersion": "apps/v1", "kind": "Deployment",
					"name": "my-deploy", "uid": ownerUID, "controller": true,
				},
			},
		},
		"spec": map[string]any{
			"replicas": int64(2),
			"template": map[string]any{
				"spec": map[string]any{
					"containers": []any{
						map[string]any{"name": "app", "image": image},
					},
				},
			},
		},
	}}
}

func TestRolloutHistory_sortedDescending(t *testing.T) {
	deploy := testDeploy("my-deploy", "uid-abc", "3")
	rs1 := testRS("rs-1", "uid-abc", "1", "nginx:1.19")
	rs2 := testRS("rs-2", "uid-abc", "2", "nginx:1.20")
	rs3 := testRS("rs-3", "uid-abc", "3", "nginx:1.21")
	rsOther := testRS("rs-other", "uid-different", "1", "nginx:1.0")

	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), deploy, rs1, rs2, rs3, rsOther)
	ref := ResourceRef{GVR: deployGVR, Namespaced: true}

	entries, err := RolloutHistory(context.Background(), dyn, ref, "default", "my-deploy")
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 3 {
		t.Fatalf("want 3 entries, got %d", len(entries))
	}
	if entries[0].Revision != 3 || entries[2].Revision != 1 {
		t.Errorf("order wrong: %v", entries)
	}
	if entries[0].Images[0] != "nginx:1.21" {
		t.Errorf("image = %q", entries[0].Images[0])
	}
}

func TestRolloutHistory_noDeploymentFound(t *testing.T) {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())
	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	_, err := RolloutHistory(context.Background(), dyn, ref, "default", "missing")
	if err == nil {
		t.Error("expected error for missing deployment")
	}
}

func TestRolloutUndo_patchesDeployment(t *testing.T) {
	deploy := testDeploy("my-deploy", "uid-abc", "2")
	rs1 := testRS("rs-1", "uid-abc", "1", "nginx:1.19")
	rs2 := testRS("rs-2", "uid-abc", "2", "nginx:1.20")
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), deploy, rs1, rs2)

	var patchCalled bool
	dyn.PrependReactor("patch", "deployments", func(_ k8stesting.Action) (bool, runtime.Object, error) {
		patchCalled = true
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "apps/v1", "kind": "Deployment",
			"metadata": map[string]any{"name": "my-deploy", "namespace": "default"},
		}}, nil
	})

	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	if err := RolloutUndo(context.Background(), dyn, ref, "default", "my-deploy", 1); err != nil {
		t.Fatal(err)
	}
	if !patchCalled {
		t.Error("expected PATCH on deployment")
	}
}

func TestRolloutUndo_revisionNotFound(t *testing.T) {
	deploy := testDeploy("my-deploy", "uid-abc", "2")
	rs2 := testRS("rs-2", "uid-abc", "2", "nginx:1.20")
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), deploy, rs2)

	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	err := RolloutUndo(context.Background(), dyn, ref, "default", "my-deploy", 5)
	if err == nil {
		t.Error("expected error for non-existent revision")
	}
}

func TestRolloutPause_sendsPatch(t *testing.T) {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())
	var got []byte
	dyn.PrependReactor("patch", "deployments", func(action k8stesting.Action) (bool, runtime.Object, error) {
		got = action.(k8stesting.PatchAction).GetPatch()
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "apps/v1", "kind": "Deployment",
			"metadata": map[string]any{"name": "d", "namespace": "default"},
		}}, nil
	})

	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	if err := RolloutPause(context.Background(), dyn, ref, "default", "d"); err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"spec":{"paused":true}}` {
		t.Errorf("pause patch = %s", got)
	}
}

func TestRolloutResume_sendsPatch(t *testing.T) {
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())
	var got []byte
	dyn.PrependReactor("patch", "deployments", func(action k8stesting.Action) (bool, runtime.Object, error) {
		got = action.(k8stesting.PatchAction).GetPatch()
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "apps/v1", "kind": "Deployment",
			"metadata": map[string]any{"name": "d", "namespace": "default"},
		}}, nil
	})

	ref := ResourceRef{GVR: deployGVR, Namespaced: true}
	if err := RolloutResume(context.Background(), dyn, ref, "default", "d"); err != nil {
		t.Fatal(err)
	}
	if string(got) != `{"spec":{"paused":false}}` {
		t.Errorf("resume patch = %s", got)
	}
}

// Suppress unused import
var _ = metav1.ObjectMeta{}
