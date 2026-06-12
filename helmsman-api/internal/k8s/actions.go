package k8s

import (
	"context"
	"fmt"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
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

// SetSuspend sets spec.suspend on a resource (CronJob or Job).
// suspend=true pauses scheduling; suspend=false resumes it.
func SetSuspend(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, suspend bool) error {
	val := "false"
	if suspend {
		val = "true"
	}
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType,
		[]byte(fmt.Sprintf(`{"spec":{"suspend":%s}}`, val)),
		metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("set suspend=%v on %s/%s: %w", suspend, ref.GVR.Resource, name, err)
	}
	return nil
}

// CancelJob suspends a Job (stops new pod creation) and deletes all running
// pods owned by it via the standard "job-name" label.
func CancelJob(ctx context.Context, b *cluster.ClientBundle, ref ResourceRef, namespace, name string) error {
	if err := SetSuspend(ctx, b.Dynamic, ref, namespace, name, true); err != nil {
		return fmt.Errorf("suspend job: %w", err)
	}
	if err := b.Typed.CoreV1().Pods(namespace).DeleteCollection(
		ctx,
		metav1.DeleteOptions{},
		metav1.ListOptions{LabelSelector: "job-name=" + name},
	); err != nil {
		return fmt.Errorf("delete pods for job %s/%s: %w", namespace, name, err)
	}
	return nil
}
