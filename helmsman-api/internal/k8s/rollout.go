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
	"k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
)

var (
	replicaSetGVR         = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "replicasets"}
	controllerRevisionGVR = schema.GroupVersionResource{Group: "apps", Version: "v1", Resource: "controllerrevisions"}
)

// RevisionEntry describes one rollout revision (ReplicaSet for Deployments,
// ControllerRevision for StatefulSets and DaemonSets).
type RevisionEntry struct {
	Revision    int64    `json:"revision"`
	Name        string   `json:"name"`
	CreatedAt   string   `json:"createdAt"`
	Images      []string `json:"images"`
	Replicas    int64    `json:"replicas"`
	ChangeCause string   `json:"changeCause,omitempty"`
}

// RolloutHistory returns rollout revision history for a workload. Deployments
// use owned ReplicaSets; StatefulSets and DaemonSets use ControllerRevisions.
// Entries are sorted by revision descending (newest first).
func RolloutHistory(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) ([]RevisionEntry, error) {
	owner, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return nil, err
	}
	switch ref.GVR.Resource {
	case "statefulsets", "daemonsets":
		return controllerRevisionHistory(ctx, dyn, owner)
	default:
		return deploymentRolloutHistory(ctx, dyn, owner)
	}
}

// RolloutUndo rolls back a workload to a previous revision. toRevision=0 means
// "the revision before the current one".
func RolloutUndo(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, toRevision int64) error {
	owner, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return err
	}
	switch ref.GVR.Resource {
	case "statefulsets", "daemonsets":
		return controllerRevisionUndo(ctx, dyn, ref, owner, namespace, name, toRevision)
	default:
		return deploymentRolloutUndo(ctx, dyn, ref, owner, namespace, name, toRevision)
	}
}

// RolloutPause pauses a Deployment rollout by setting spec.paused=true.
func RolloutPause(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) error {
	if ref.GVR.Resource != "deployments" {
		return apierrors.NewBadRequest("pause is only supported for deployments")
	}
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
	if ref.GVR.Resource != "deployments" {
		return apierrors.NewBadRequest("resume is only supported for deployments")
	}
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

func deploymentRolloutHistory(ctx context.Context, dyn dynamic.Interface, owner *unstructured.Unstructured) ([]RevisionEntry, error) {
	ownerUID := string(owner.GetUID())
	labelSelector, err := workloadLabelSelector(owner)
	if err != nil {
		return nil, err
	}

	rsList, err := dyn.Resource(replicaSetGVR).Namespace(owner.GetNamespace()).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
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

func deploymentRolloutUndo(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, owner *unstructured.Unstructured, namespace, name string, toRevision int64) error {
	ownerUID := string(owner.GetUID())

	if toRevision == 0 {
		curStr := owner.GetAnnotations()["deployment.kubernetes.io/revision"]
		cur, _ := strconv.ParseInt(curStr, 10, 64)
		toRevision = cur - 1
	}
	if toRevision <= 0 {
		return apierrors.NewBadRequest("no previous revision available")
	}

	labelSelector, err := workloadLabelSelector(owner)
	if err != nil {
		return err
	}

	rsList, err := dyn.Resource(replicaSetGVR).Namespace(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
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

func controllerRevisionHistory(ctx context.Context, dyn dynamic.Interface, owner *unstructured.Unstructured) ([]RevisionEntry, error) {
	crs, err := listControlledRevisions(ctx, dyn, owner)
	if err != nil {
		return nil, err
	}

	var entries []RevisionEntry
	for _, cr := range crs {
		rev, found, err := unstructured.NestedInt64(cr.Object, "revision")
		if err != nil || !found {
			continue
		}

		replicas, _, _ := unstructured.NestedInt64(cr.Object, "data", "spec", "replicas")
		images := extractImagesFromCRData(cr)
		changeCause := cr.GetAnnotations()["kubernetes.io/change-cause"]
		createdAt := ""
		if ts := cr.GetCreationTimestamp(); !ts.IsZero() {
			createdAt = ts.UTC().Format("2006-01-02T15:04:05Z")
		}

		entries = append(entries, RevisionEntry{
			Revision:    rev,
			Name:        cr.GetName(),
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

func controllerRevisionUndo(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, owner *unstructured.Unstructured, namespace, name string, toRevision int64) error {
	crs, err := listControlledRevisions(ctx, dyn, owner)
	if err != nil {
		return err
	}
	if len(crs) == 0 {
		return apierrors.NewBadRequest("no revision history available")
	}

	target, err := resolveControllerRevisionTarget(crs, toRevision)
	if err != nil {
		return err
	}

	patch, err := extractCRPatchData(target)
	if err != nil {
		return err
	}

	_, err = dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.StrategicMergePatchType, patch, metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("rollback %s/%s to revision %d: %w", namespace, name, toRevision, err)
	}
	return nil
}

func listControlledRevisions(ctx context.Context, dyn dynamic.Interface, owner *unstructured.Unstructured) ([]*unstructured.Unstructured, error) {
	ownerUID := string(owner.GetUID())
	labelSelector, err := workloadLabelSelector(owner)
	if err != nil {
		return nil, err
	}

	crList, err := dyn.Resource(controllerRevisionGVR).Namespace(owner.GetNamespace()).List(ctx, metav1.ListOptions{
		LabelSelector: labelSelector,
	})
	if err != nil {
		return nil, fmt.Errorf("list controllerrevisions: %w", err)
	}

	var crs []*unstructured.Unstructured
	for i := range crList.Items {
		cr := &crList.Items[i]
		if ownedBy(cr, ownerUID) {
			crs = append(crs, cr)
		}
	}
	return crs, nil
}

func resolveControllerRevisionTarget(crs []*unstructured.Unstructured, toRevision int64) (*unstructured.Unstructured, error) {
	if toRevision == 0 {
		if len(crs) <= 1 {
			return nil, apierrors.NewBadRequest("no previous revision available")
		}
		sort.Slice(crs, func(i, j int) bool {
			ri, _, _ := unstructured.NestedInt64(crs[i].Object, "revision")
			rj, _, _ := unstructured.NestedInt64(crs[j].Object, "revision")
			return ri < rj
		})
		return crs[len(crs)-2], nil
	}

	for _, cr := range crs {
		rev, found, _ := unstructured.NestedInt64(cr.Object, "revision")
		if found && rev == toRevision {
			return cr, nil
		}
	}
	return nil, apierrors.NewNotFound(
		schema.GroupResource{Group: "apps", Resource: "controllerrevisions"},
		fmt.Sprintf("revision %d", toRevision),
	)
}

func extractCRPatchData(cr *unstructured.Unstructured) ([]byte, error) {
	data, found, err := unstructured.NestedMap(cr.Object, "data")
	if err != nil || !found {
		return nil, fmt.Errorf("cannot read controllerrevision data: %w", err)
	}
	patch, err := json.Marshal(data)
	if err != nil {
		return nil, fmt.Errorf("marshal controllerrevision data: %w", err)
	}
	return patch, nil
}

func workloadLabelSelector(owner *unstructured.Unstructured) (string, error) {
	matchLabels, found, err := unstructured.NestedStringMap(owner.Object, "spec", "selector", "matchLabels")
	if err != nil {
		return "", fmt.Errorf("read spec.selector.matchLabels: %w", err)
	}
	if !found || len(matchLabels) == 0 {
		return "", fmt.Errorf("workload has no spec.selector.matchLabels")
	}
	return labels.SelectorFromSet(matchLabels).String(), nil
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
	return imagesFromContainers(containers)
}

func extractImagesFromCRData(cr *unstructured.Unstructured) []string {
	containers, _, _ := unstructured.NestedSlice(cr.Object, "data", "spec", "template", "spec", "containers")
	return imagesFromContainers(containers)
}

func imagesFromContainers(containers []any) []string {
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
