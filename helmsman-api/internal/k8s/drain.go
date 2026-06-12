package k8s

import (
	"context"
	"fmt"

	corev1 "k8s.io/api/core/v1"
	policyv1 "k8s.io/api/policy/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

var nodeGVR = schema.GroupVersionResource{Group: "", Version: "v1", Resource: "nodes"}

// DrainResult summarises what happened during a drain.
type DrainResult struct {
	Node    string `json:"node"`
	Evicted int    `json:"evicted"`
	Skipped int    `json:"skipped"`
	Failed  int    `json:"failed"`
}

// DrainNode cordons a node and evicts all pods except DaemonSet-owned and
// static/mirror pods. gracePeriodSec may be nil to use each pod's default.
// Eviction failures are counted in DrainResult.Failed rather than aborting,
// matching kubectl drain behaviour.
func DrainNode(ctx context.Context, b *cluster.ClientBundle, nodeName string, gracePeriodSec *int64) (DrainResult, error) {
	result := DrainResult{Node: nodeName}

	// Cordon: mark node unschedulable.
	_, err := b.Dynamic.Resource(nodeGVR).Patch(
		ctx, nodeName, types.MergePatchType,
		[]byte(`{"spec":{"unschedulable":true}}`),
		metav1.PatchOptions{},
	)
	if err != nil {
		return result, fmt.Errorf("cordon node %s: %w", nodeName, err)
	}

	// List all pods on this node.
	pods, err := b.Typed.CoreV1().Pods("").List(ctx, metav1.ListOptions{
		FieldSelector: "spec.nodeName=" + nodeName,
	})
	if err != nil {
		return result, fmt.Errorf("list pods on %s: %w", nodeName, err)
	}

	for _, pod := range pods.Items {
		if skipForDrain(&pod) {
			result.Skipped++
			continue
		}
		eviction := &policyv1.Eviction{
			ObjectMeta: metav1.ObjectMeta{
				Name:      pod.Name,
				Namespace: pod.Namespace,
			},
		}
		if gracePeriodSec != nil {
			eviction.DeleteOptions = &metav1.DeleteOptions{
				GracePeriodSeconds: gracePeriodSec,
			}
		}
		if err := b.Typed.PolicyV1().Evictions(pod.Namespace).Evict(ctx, eviction); err != nil {
			result.Failed++
		} else {
			result.Evicted++
		}
	}
	return result, nil
}

// skipForDrain returns true for pods that should not be evicted:
// DaemonSet-owned pods and mirror/static pods.
func skipForDrain(pod *corev1.Pod) bool {
	if _, isMirror := pod.Annotations["kubernetes.io/config.mirror"]; isMirror {
		return true
	}
	for _, ref := range pod.OwnerReferences {
		if ref.Kind == "DaemonSet" {
			return true
		}
	}
	return false
}
