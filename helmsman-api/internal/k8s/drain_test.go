package k8s

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	fakek8s "k8s.io/client-go/kubernetes/fake"
	k8stesting "k8s.io/client-go/testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

func makePod(name, node string, ownerKind string) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "default"},
		Spec:       corev1.PodSpec{NodeName: node},
	}
	if ownerKind != "" {
		ctrl := true
		pod.OwnerReferences = []metav1.OwnerReference{
			{Kind: ownerKind, Controller: &ctrl},
		}
	}
	return pod
}

func mirrorPod(name, node string) *corev1.Pod {
	pod := makePod(name, node, "")
	pod.Annotations = map[string]string{"kubernetes.io/config.mirror": "some-hash"}
	return pod
}

func TestDrainNode_evictsNormalPods(t *testing.T) {
	normalPod := makePod("app-pod", "node-1", "ReplicaSet")
	dsPod := makePod("ds-pod", "node-1", "DaemonSet")
	staticPod := mirrorPod("static-pod", "node-1")

	fakeTyped := fakek8s.NewSimpleClientset(normalPod, dsPod, staticPod)
	fakeDynClient := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())

	// Intercept the cordon PATCH — fake dynamic client has no node object.
	fakeDynClient.PrependReactor("patch", "nodes", func(action k8stesting.Action) (bool, runtime.Object, error) {
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "v1", "kind": "Node",
			"metadata": map[string]any{"name": "node-1"},
		}}, nil
	})

	evicted := []string{}
	fakeTyped.PrependReactor("create", "pods", func(action k8stesting.Action) (bool, runtime.Object, error) {
		if action.GetSubresource() == "eviction" {
			evicted = append(evicted, action.(k8stesting.CreateAction).GetObject().(metav1.Object).GetName())
		}
		return true, nil, nil
	})

	b := &cluster.ClientBundle{Dynamic: fakeDynClient, Typed: fakeTyped}
	result, err := DrainNode(context.Background(), b, "node-1", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(evicted) != 1 || evicted[0] != "app-pod" {
		t.Errorf("evicted = %v, want [app-pod]", evicted)
	}
	if result.Evicted != 1 {
		t.Errorf("DrainResult.Evicted = %d, want 1", result.Evicted)
	}
	if result.Skipped != 2 {
		t.Errorf("DrainResult.Skipped = %d, want 2 (daemonset + static)", result.Skipped)
	}
}

func TestDrainNode_cordonsNode(t *testing.T) {
	fakeTyped := fakek8s.NewSimpleClientset()
	fakeDynClient := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())

	var cordoned bool
	fakeDynClient.PrependReactor("patch", "nodes", func(action k8stesting.Action) (bool, runtime.Object, error) {
		cordoned = true
		return true, &unstructured.Unstructured{Object: map[string]any{
			"apiVersion": "v1", "kind": "Node",
			"metadata": map[string]any{"name": "node-1"},
		}}, nil
	})

	b := &cluster.ClientBundle{Dynamic: fakeDynClient, Typed: fakeTyped}
	_, err := DrainNode(context.Background(), b, "node-1", nil)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !cordoned {
		t.Error("expected node to be cordoned via PATCH")
	}
}
