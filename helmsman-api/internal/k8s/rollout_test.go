package k8s

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
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
		"spec": map[string]any{
			"selector": map[string]any{
				"matchLabels": map[string]any{"app": name},
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
			"labels": map[string]any{"app": "my-deploy"},
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

var statefulSetGVR = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "statefulsets"}
var daemonSetGVR = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "daemonsets"}

func testStatefulSet(name, uid string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "StatefulSet",
		"metadata": map[string]any{
			"name": name, "namespace": "default", "uid": uid,
		},
		"spec": map[string]any{
			"selector": map[string]any{
				"matchLabels": map[string]any{"app": name},
			},
		},
	}}
}

func testControllerRevision(name, ownerUID, ownerKind string, revision int64, image string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1", "kind": "ControllerRevision",
		"metadata": map[string]any{
			"name": name, "namespace": "default",
			"creationTimestamp": "2026-01-01T00:00:00Z",
			"labels":              map[string]any{"app": "my-sts"},
			"ownerReferences": []any{
				map[string]any{
					"apiVersion": "apps/v1", "kind": ownerKind,
					"name": "my-sts", "uid": ownerUID, "controller": true,
				},
			},
		},
		"revision": revision,
		"data": map[string]any{
			"spec": map[string]any{
				"template": map[string]any{
					"spec": map[string]any{
						"containers": []any{
							map[string]any{"name": "app", "image": image},
						},
					},
				},
			},
		},
	}}
}

func TestControllerRevisionHistory_sortedDescending(t *testing.T) {
	sts := testStatefulSet("my-sts", "uid-sts")
	cr1 := testControllerRevision("cr-1", "uid-sts", "StatefulSet", 1, "nginx:1.19")
	cr2 := testControllerRevision("cr-2", "uid-sts", "StatefulSet", 2, "nginx:1.20")
	crOther := testControllerRevision("cr-other", "uid-other", "StatefulSet", 1, "nginx:1.0")

	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), sts, cr1, cr2, crOther)
	ref := ResourceRef{GVR: statefulSetGVR, Namespaced: true}

	entries, err := RolloutHistory(context.Background(), dyn, ref, "default", "my-sts")
	if err != nil {
		t.Fatal(err)
	}
	if len(entries) != 2 {
		t.Fatalf("want 2 entries, got %d", len(entries))
	}
	if entries[0].Revision != 2 || entries[1].Revision != 1 {
		t.Errorf("order wrong: %+v", entries)
	}
	if entries[0].Images[0] != "nginx:1.20" {
		t.Errorf("image = %q", entries[0].Images[0])
	}
}

func TestControllerRevisionUndo_strategicMergePatch(t *testing.T) {
	sts := testStatefulSet("my-sts", "uid-sts")
	cr1 := testControllerRevision("cr-1", "uid-sts", "StatefulSet", 1, "nginx:1.19")
	cr2 := testControllerRevision("cr-2", "uid-sts", "StatefulSet", 2, "nginx:1.20")
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), sts, cr1, cr2)

	var patchType types.PatchType
	var patchData []byte
	dyn.PrependReactor("patch", "statefulsets", func(action k8stesting.Action) (bool, runtime.Object, error) {
		pa := action.(k8stesting.PatchAction)
		patchType = pa.GetPatchType()
		patchData = pa.GetPatch()
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "apps/v1", "kind": "StatefulSet",
			"metadata": map[string]any{"name": "my-sts", "namespace": "default"},
		}}, nil
	})

	ref := ResourceRef{GVR: statefulSetGVR, Namespaced: true}
	if err := RolloutUndo(context.Background(), dyn, ref, "default", "my-sts", 1); err != nil {
		t.Fatal(err)
	}
	if patchType != types.StrategicMergePatchType {
		t.Errorf("patch type = %v, want StrategicMergePatchType", patchType)
	}
	if len(patchData) == 0 {
		t.Error("expected non-empty patch data")
	}
}

func TestControllerRevisionUndo_noPreviousRevision(t *testing.T) {
	sts := testStatefulSet("my-sts", "uid-sts")
	cr1 := testControllerRevision("cr-1", "uid-sts", "StatefulSet", 1, "nginx:1.19")
	dyn := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), sts, cr1)

	ref := ResourceRef{GVR: statefulSetGVR, Namespaced: true}
	err := RolloutUndo(context.Background(), dyn, ref, "default", "my-sts", 0)
	if err == nil {
		t.Fatal("expected error when only one revision exists")
	}
}

func TestRolloutPause_rejectsStatefulSet(t *testing.T) {
	ref := ResourceRef{GVR: statefulSetGVR, Namespaced: true}
	err := RolloutPause(context.Background(), dynamicfake.NewSimpleDynamicClient(runtime.NewScheme()), ref, "default", "my-sts")
	if err == nil {
		t.Fatal("expected error for statefulset pause")
	}
}

// Suppress unused import
var _ = metav1.ObjectMeta{}
