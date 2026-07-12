package k8s

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/dynamic"
	"sigs.k8s.io/yaml"
)

const fieldManager = "k67s"

// ListOptions are the pass-through list filters from query params.
type ListOptions struct {
	LabelSelector string
	FieldSelector string
}

func dynResource(dyn dynamic.Interface, ref ResourceRef, namespace string) dynamic.ResourceInterface {
	r := dyn.Resource(ref.GVR)
	if ref.Namespaced {
		return r.Namespace(namespace)
	}
	return r
}

// FetchTable lists resources in the server-side Table format. It issues a raw
// REST GET with the Table Accept header and JSON-decodes the result, avoiding
// per-type serializer wiring.
func FetchTable(ctx context.Context, b *cluster.ClientBundle, ref ResourceRef, namespace string, opts ListOptions) (*metav1.Table, error) {
	req := b.Discovery.RESTClient().Get().
		AbsPath(absPath(ref, namespace)).
		SetHeader("Accept", "application/json;as=Table;v=v1;g=meta.k8s.io, application/json")
	if opts.LabelSelector != "" {
		req = req.Param("labelSelector", opts.LabelSelector)
	}
	if opts.FieldSelector != "" {
		req = req.Param("fieldSelector", opts.FieldSelector)
	}
	raw, err := req.Do(ctx).Raw()
	if err != nil {
		return nil, fmt.Errorf("list %s: %w", ref.GVR.Resource, err)
	}
	var table metav1.Table
	if err := json.Unmarshal(raw, &table); err != nil {
		return nil, fmt.Errorf("decode table for %s: %w", ref.GVR.Resource, err)
	}
	return &table, nil
}

func absPath(ref ResourceRef, namespace string) string {
	gv := ref.GVR.GroupVersion()
	var prefix string
	if gv.Group == "" {
		prefix = "/api/" + gv.Version
	} else {
		prefix = "/apis/" + gv.Group + "/" + gv.Version
	}
	if ref.Namespaced && namespace != "" {
		return prefix + "/namespaces/" + namespace + "/" + ref.GVR.Resource
	}
	return prefix + "/" + ref.GVR.Resource
}

// Get returns a single object.
func Get(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) (*unstructured.Unstructured, error) {
	obj, err := dynResource(dyn, ref, namespace).Get(ctx, name, metav1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("get %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return obj, nil
}

// YAML returns a single object serialized as YAML.
func YAML(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string) ([]byte, error) {
	obj, err := Get(ctx, dyn, ref, namespace, name)
	if err != nil {
		return nil, err
	}
	out, err := yaml.Marshal(obj.Object)
	if err != nil {
		return nil, fmt.Errorf("marshal yaml: %w", err)
	}
	return out, nil
}

// Delete removes an object with optional grace period and propagation policy.
func Delete(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, opts metav1.DeleteOptions) error {
	if err := dynResource(dyn, ref, namespace).Delete(ctx, name, opts); err != nil {
		return fmt.Errorf("delete %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return nil
}

// Patch applies a merge or JSON patch to an object.
func Patch(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, namespace, name string, pt types.PatchType, data []byte) (*unstructured.Unstructured, error) {
	obj, err := dynResource(dyn, ref, namespace).Patch(ctx, name, pt, data, metav1.PatchOptions{})
	if err != nil {
		return nil, fmt.Errorf("patch %s/%s: %w", ref.GVR.Resource, name, err)
	}
	return obj, nil
}

// ParseManifest decodes a YAML/JSON manifest into an unstructured object and
// returns its embedded GVK.
func ParseManifest(manifest []byte) (*unstructured.Unstructured, schema.GroupVersionKind, error) {
	jsonBytes, err := yaml.YAMLToJSON(manifest)
	if err != nil {
		return nil, schema.GroupVersionKind{}, fmt.Errorf("yaml to json: %w", err)
	}
	obj := &unstructured.Unstructured{}
	if err := obj.UnmarshalJSON(jsonBytes); err != nil {
		return nil, schema.GroupVersionKind{}, fmt.Errorf("decode manifest: %w", err)
	}
	gvk := obj.GroupVersionKind()
	if gvk.Empty() {
		return nil, schema.GroupVersionKind{}, fmt.Errorf("manifest missing apiVersion/kind")
	}
	return obj, gvk, nil
}

// Apply performs a server-side apply of a manifest. ref must already be
// resolved from the manifest's GVK by the caller.
func Apply(ctx context.Context, dyn dynamic.Interface, ref ResourceRef, obj *unstructured.Unstructured) (*unstructured.Unstructured, error) {
	stripServerFields(obj)
	data, err := obj.MarshalJSON()
	if err != nil {
		return nil, fmt.Errorf("marshal apply: %w", err)
	}
	res, err := dynResource(dyn, ref, obj.GetNamespace()).Patch(
		ctx, obj.GetName(), types.ApplyPatchType, data,
		metav1.PatchOptions{FieldManager: fieldManager, Force: ptrBool(true)},
	)
	if err != nil {
		return nil, fmt.Errorf("apply %s/%s: %w", ref.GVR.Resource, obj.GetName(), err)
	}
	return res, nil
}

const lastAppliedConfigAnnotation = "kubectl.kubernetes.io/last-applied-configuration"

// stripServerFields removes server-managed fields that server-side apply rejects
// (notably metadata.managedFields) or that should not be carried in a manifest.
// This lets a client round-trip a fetched object's YAML straight back into apply.
func stripServerFields(obj *unstructured.Unstructured) {
	for _, field := range [][]string{
		{"metadata", "managedFields"},
		{"metadata", "resourceVersion"},
		{"metadata", "uid"},
		{"metadata", "creationTimestamp"},
		{"metadata", "generation"},
		{"metadata", "selfLink"},
		{"metadata", "deletionTimestamp"},
		{"metadata", "deletionGracePeriodSeconds"},
		{"metadata", "ownerReferences"},
		{"status"},
	} {
		unstructured.RemoveNestedField(obj.Object, field...)
	}
	stripLastAppliedAnnotation(obj)
}

func stripLastAppliedAnnotation(obj *unstructured.Unstructured) {
	annotations, found, err := unstructured.NestedStringMap(obj.Object, "metadata", "annotations")
	if err != nil || !found {
		return
	}
	delete(annotations, lastAppliedConfigAnnotation)
	if len(annotations) == 0 {
		unstructured.RemoveNestedField(obj.Object, "metadata", "annotations")
		return
	}
	_ = unstructured.SetNestedStringMap(obj.Object, annotations, "metadata", "annotations")
}

func ptrBool(b bool) *bool { return &b }
