package k8s

import (
	"context"
	"errors"
	"fmt"

	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
)

// ErrPVCStorageShrink is returned when a resize request is smaller than the
// current PVC storage request.
var ErrPVCStorageShrink = errors.New("may not decrease storage request")

func resizePVCPatch(storage string) []byte {
	return []byte(fmt.Sprintf(`{"spec":{"resources":{"requests":{"storage":%q}}}}`, storage))
}

// ResizePVC increases a PVC's spec.resources.requests.storage via merge patch.
// Shrinking is rejected before the API call when the current request is known.
func ResizePVC(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name, storage string) error {
	newQty, err := resource.ParseQuantity(storage)
	if err != nil {
		return fmt.Errorf("invalid storage quantity: %w", err)
	}

	obj, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return err
	}

	if currentStr, found, _ := unstructured.NestedString(obj.Object, "spec", "resources", "requests", "storage"); found {
		currentQty, parseErr := resource.ParseQuantity(currentStr)
		if parseErr == nil && newQty.Cmp(currentQty) < 0 {
			return fmt.Errorf("%w: current %s, requested %s", ErrPVCStorageShrink, currentStr, storage)
		}
	}

	_, err = dyn.Resource(ref.GVR).Namespace(namespace).Patch(
		ctx, name, types.MergePatchType, resizePVCPatch(storage), metav1.PatchOptions{},
	)
	if err != nil {
		return fmt.Errorf("resize %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}
