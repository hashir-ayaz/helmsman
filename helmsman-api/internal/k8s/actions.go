package k8s

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
)

func scalePatch(replicas int32) []byte {
	return []byte(fmt.Sprintf(`{"spec":{"replicas":%d}}`, replicas))
}

func restartPatch(restartedAt string) []byte {
	return []byte(fmt.Sprintf(
		`{"spec":{"template":{"metadata":{"annotations":{"kubectl.kubernetes.io/restartedAt":%q}}}}}`,
		restartedAt,
	))
}

// Scale sets the replica count via the resource's scale subresource (works for
// deployments, statefulsets, replicasets).
func Scale(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, replicas int32) error {
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType, scalePatch(replicas), metav1.PatchOptions{}, "scale",
	)
	if err != nil {
		return fmt.Errorf("scale %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}

// Restart triggers a rolling restart by stamping the pod-template restartedAt
// annotation (the same mechanism as `kubectl rollout restart`). restartedAt is
// supplied by the caller to keep the operation deterministic.
func Restart(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name, restartedAt string) error {
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.StrategicMergePatchType, restartPatch(restartedAt), metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("restart %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}
