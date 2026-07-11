package k8s

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	dynamicfake "k8s.io/client-go/dynamic/fake"
)

var cmGVR = schema.GroupVersionResource{Version: "v1", Resource: "configmaps"}

func newCM(name string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "ConfigMap",
		"metadata": map[string]any{"name": name, "namespace": "default"},
	}}
}

func fakeDyn(objs ...runtime.Object) *dynamicfake.FakeDynamicClient {
	return dynamicfake.NewSimpleDynamicClient(runtime.NewScheme(), objs...)
}

func TestGetAndDelete(t *testing.T) {
	dyn := fakeDyn(newCM("cm-1"))
	ref := ResourceRef{GVR: cmGVR, Namespaced: true}
	ctx := context.Background()

	obj, err := Get(ctx, dyn, ref, "default", "cm-1")
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if obj.GetName() != "cm-1" {
		t.Errorf("name = %q", obj.GetName())
	}

	if err := Delete(ctx, dyn, ref, "default", "cm-1"); err != nil {
		t.Fatalf("Delete: %v", err)
	}
	if _, err := dyn.Resource(cmGVR).Namespace("default").Get(ctx, "cm-1", metav1.GetOptions{}); err == nil {
		t.Error("expected cm-1 to be gone")
	}
}

func TestParseApply(t *testing.T) {
	yaml := []byte("apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: parsed\n  namespace: default\n")
	obj, gvk, err := ParseManifest(yaml)
	if err != nil {
		t.Fatalf("ParseManifest: %v", err)
	}
	if gvk.Kind != "ConfigMap" {
		t.Errorf("kind = %q", gvk.Kind)
	}
	if obj.GetName() != "parsed" {
		t.Errorf("name = %q", obj.GetName())
	}
}

func TestStripServerFields(t *testing.T) {
	obj := &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "apps/v1",
		"kind":       "Deployment",
		"metadata": map[string]any{
			"name":                       "web",
			"namespace":                  "default",
			"uid":                        "abc",
			"resourceVersion":            "42",
			"generation":                 int64(3),
			"creationTimestamp":          "2024-01-01T00:00:00Z",
			"deletionTimestamp":          "2024-01-02T00:00:00Z",
			"deletionGracePeriodSeconds": int64(30),
			"ownerReferences": []any{
				map[string]any{"apiVersion": "apps/v1", "kind": "ReplicaSet", "name": "web-abc"},
			},
			"annotations": map[string]any{
				"kubectl.kubernetes.io/last-applied-configuration": "{}",
				"deployment.kubernetes.io/revision":                "2",
			},
		},
		"status": map[string]any{"replicas": int64(1)},
	}}

	stripServerFields(obj)

	if _, ok, _ := unstructured.NestedFieldCopy(obj.Object, "status"); ok {
		t.Error("expected status stripped")
	}
	if _, ok, _ := unstructured.NestedFieldCopy(obj.Object, "metadata", "uid"); ok {
		t.Error("expected uid stripped")
	}
	if _, ok, _ := unstructured.NestedFieldCopy(obj.Object, "metadata", "ownerReferences"); ok {
		t.Error("expected ownerReferences stripped")
	}
	ann, _, _ := unstructured.NestedStringMap(obj.Object, "metadata", "annotations")
	if _, ok := ann[lastAppliedConfigAnnotation]; ok {
		t.Error("expected last-applied-configuration annotation stripped")
	}
	if ann["deployment.kubernetes.io/revision"] != "2" {
		t.Error("expected other annotations preserved")
	}
}
