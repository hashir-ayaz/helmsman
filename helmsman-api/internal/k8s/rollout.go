package k8s

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strconv"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
)

var replicaSetGVR = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "replicasets"}

// RevisionEntry describes one rollout revision (one ReplicaSet owned by a Deployment).
type RevisionEntry struct {
	Revision    int64    `json:"revision"`
	Name        string   `json:"name"`
	CreatedAt   string   `json:"createdAt"`
	Images      []string `json:"images"`
	Replicas    int64    `json:"replicas"`
	ChangeCause string   `json:"changeCause,omitempty"`
}

// RolloutHistory returns the revision history for a Deployment by inspecting
// owned ReplicaSets. Returns entries sorted by revision descending (newest first).
func RolloutHistory(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) ([]RevisionEntry, error) {
	owner, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return nil, err
	}
	ownerUID := string(owner.GetUID())

	rsList, err := dyn.Resource(replicaSetGVR).Namespace(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return nil, fmt.Errorf("list replicasets: %w", err)
	}

	var entries []RevisionEntry
	for _, item := range rsList.Items {
		if !ownedBy(&item, ownerUID) {
			continue
		}
		revStr := item.GetAnnotations()["deployment.kubernetes.io/revision"]
		if revStr == "" {
			continue
		}
		rev, _ := strconv.ParseInt(revStr, 10, 64)

		replicas, _, _ := unstructured.NestedInt64(item.Object, "spec", "replicas")
		images := extractImages(&item)
		changeCause := item.GetAnnotations()["kubernetes.io/change-cause"]
		createdAt := ""
		if ts := item.GetCreationTimestamp(); !ts.IsZero() {
			createdAt = ts.UTC().Format("2006-01-02T15:04:05Z")
		}

		entries = append(entries, RevisionEntry{
			Revision:    rev,
			Name:        item.GetName(),
			CreatedAt:   createdAt,
			Images:      images,
			Replicas:    replicas,
			ChangeCause: changeCause,
		})
	}

	sort.Slice(entries, func(i, j int) bool {
		return entries[i].Revision > entries[j].Revision
	})
	return entries, nil
}

// RolloutUndo rolls back a Deployment to a previous revision. toRevision=0
// means "the revision before the current one".
func RolloutUndo(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, toRevision int64) error {
	owner, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return err
	}
	ownerUID := string(owner.GetUID())

	if toRevision == 0 {
		curStr := owner.GetAnnotations()["deployment.kubernetes.io/revision"]
		cur, _ := strconv.ParseInt(curStr, 10, 64)
		toRevision = cur - 1
	}
	if toRevision <= 0 {
		return apierrors.NewBadRequest("no previous revision available")
	}

	rsList, err := dyn.Resource(replicaSetGVR).Namespace(namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return fmt.Errorf("list replicasets: %w", err)
	}

	var target *unstructured.Unstructured
	for i := range rsList.Items {
		item := &rsList.Items[i]
		if !ownedBy(item, ownerUID) {
			continue
		}
		revStr := item.GetAnnotations()["deployment.kubernetes.io/revision"]
		rev, _ := strconv.ParseInt(revStr, 10, 64)
		if rev == toRevision {
			target = item
			break
		}
	}
	if target == nil {
		return apierrors.NewNotFound(
			schema.GroupResource{Group: "apps", Resource: "replicasets"},
			fmt.Sprintf("revision %d", toRevision),
		)
	}

	tmpl, found, err := unstructured.NestedMap(target.Object, "spec", "template")
	if err != nil || !found {
		return fmt.Errorf("cannot read spec.template from revision %d: %w", toRevision, err)
	}

	patch, err := json.Marshal(map[string]any{
		"spec": map[string]any{"template": tmpl},
	})
	if err != nil {
		return fmt.Errorf("marshal rollback patch: %w", err)
	}

	_, err = dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType, patch, metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("rollback %s/%s to revision %d: %w", namespace, name, toRevision, err)
	}
	return nil
}

// RolloutPause pauses a Deployment rollout by setting spec.paused=true.
func RolloutPause(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) error {
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType,
		[]byte(`{"spec":{"paused":true}}`),
		metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("pause %s/%s: %w", namespace, name, err)
	}
	return nil
}

// RolloutResume resumes a paused Deployment by setting spec.paused=false.
func RolloutResume(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) error {
	_, err := dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType,
		[]byte(`{"spec":{"paused":false}}`),
		metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("resume %s/%s: %w", namespace, name, err)
	}
	return nil
}

// ownedBy returns true if item has an ownerReference with the given UID.
func ownedBy(item *unstructured.Unstructured, uid string) bool {
	for _, ref := range item.GetOwnerReferences() {
		if string(ref.UID) == uid {
			return true
		}
	}
	return false
}

// extractImages returns the container images from spec.template.spec.containers.
func extractImages(item *unstructured.Unstructured) []string {
	containers, _, _ := unstructured.NestedSlice(item.Object, "spec", "template", "spec", "containers")
	var images []string
	for _, c := range containers {
		cm, ok := c.(map[string]any)
		if !ok {
			continue
		}
		if img, ok := cm["image"].(string); ok && img != "" {
			images = append(images, img)
		}
	}
	return images
}
