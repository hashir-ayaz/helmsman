package k8s

import (
	"fmt"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

// ResourceRef is a resolved resource: its GVR and whether it is namespaced.
type ResourceRef struct {
	GVR        schema.GroupVersionResource
	Namespaced bool
}

// Resolve turns a URL resource identifier ("pods", "deployments",
// "deployments.apps", "virtualservices.networking.istio.io") into a concrete
// GVR using the cluster's RESTMapper.
func Resolve(mapper meta.RESTMapper, resourceParam string) (ResourceRef, error) {
	gr := schema.ParseGroupResource(resourceParam)
	gvr, err := resourceFor(mapper, schema.GroupVersionResource{Group: gr.Group, Resource: gr.Resource})
	if err != nil {
		return ResourceRef{}, fmt.Errorf("unknown resource %q: %w", resourceParam, err)
	}
	gvk, err := mapper.KindFor(gvr)
	if err != nil {
		return ResourceRef{}, fmt.Errorf("kind for %q: %w", resourceParam, err)
	}
	mapping, err := mapper.RESTMapping(gvk.GroupKind(), gvk.Version)
	if err != nil {
		return ResourceRef{}, fmt.Errorf("mapping for %q: %w", resourceParam, err)
	}
	return ResourceRef{
		GVR:        gvr,
		Namespaced: mapping.Scope.Name() == meta.RESTScopeNameNamespace,
	}, nil
}

// resourceFor resolves a partially specified resource to a single GVR. When the
// caller omits a group, multiple candidates may match; the deprecated
// "extensions" group is skipped in favour of a current group (e.g. "apps" for
// deployments). On real clusters extensions/* is no longer served, so this only
// affects ambiguous group-less lookups against in-memory test mappers.
func resourceFor(mapper meta.RESTMapper, input schema.GroupVersionResource) (schema.GroupVersionResource, error) {
	if input.Group == "" {
		if gvrs, err := mapper.ResourcesFor(input); err == nil {
			for _, gvr := range gvrs {
				if gvr.Group != "extensions" {
					return gvr, nil
				}
			}
		}
	}
	return mapper.ResourceFor(input)
}
