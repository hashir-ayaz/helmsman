package handler

import (
	"io"
	"log"
	"net/http"
	"strconv"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/types"
)

type ResourceHandler struct{ provider cluster.Provider }

func (h *ResourceHandler) fail(w http.ResponseWriter, err error) {
	code, msg := statusFromK8sErr(err)
	writeError(w, code, msg)
}

// List godoc
//
//	@Summary	List resources (server-side table)
//	@Tags		resources
//	@Produce	json
//	@Param		ctx			path		string	true	"Context name or _current"
//	@Param		resource	path		string	true	"Resource (e.g. pods, deployments.apps)"
//	@Success	200			{object}	APIResponse{data=TablePayload}
//	@Router		/api/v1/contexts/{ctx}/resources/{resource} [get]
func (h *ResourceHandler) List(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	opts := k8s.ListOptions{
		LabelSelector: r.URL.Query().Get("labelSelector"),
		FieldSelector: r.URL.Query().Get("fieldSelector"),
	}
	table, err := k8s.FetchTable(r.Context(), b, ref, r.PathValue("ns"), opts)
	if err != nil {
		h.fail(w, err)
		return
	}
	payload := tableToPayload(table)
	if isEventList(ref) {
		sortPayloadByLastSeenDesc(&payload)
	}
	writeSuccess(w, payload)
}

func isEventList(ref k8s.ResourceRef) bool {
	return ref.GVR.Resource == "events"
}

// Get godoc
//
//	@Summary	Get one resource
//	@Tags		resources
//	@Produce	json
//	@Success	200	{object}	APIResponse
//	@Router		/api/v1/contexts/{ctx}/resources/{resource}/{name} [get]
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name} [get]
func (h *ResourceHandler) Get(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	if msg, bad := scopeMismatch(ref, r.PathValue("ns")); bad {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	obj, err := k8s.Get(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"))
	if err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, obj.Object)
}

// YAML godoc
//
//	@Summary	Get one resource as YAML
//	@Tags		resources
//	@Produce	plain
//	@Router		/api/v1/contexts/{ctx}/resources/{resource}/{name}/yaml [get]
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}/yaml [get]
func (h *ResourceHandler) YAML(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	if msg, bad := scopeMismatch(ref, r.PathValue("ns")); bad {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	out, err := k8s.YAML(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"))
	if err != nil {
		h.fail(w, err)
		return
	}
	w.Header().Set("Content-Type", "application/yaml")
	w.WriteHeader(http.StatusOK)
	w.Write(out)
}

// Delete godoc
//
//	@Summary	Delete one resource
//	@Tags		resources
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/resources/{resource}/{name} [delete]
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name} [delete]
func (h *ResourceHandler) Delete(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	if msg, bad := scopeMismatch(ref, r.PathValue("ns")); bad {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	opts, err := parseDeleteOptions(r)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	if err := k8s.Delete(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), opts); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"deleted": r.PathValue("name")})
}

func parseDeleteOptions(r *http.Request) (metav1.DeleteOptions, error) {
	opts := metav1.DeleteOptions{}
	q := r.URL.Query()
	if gps := q.Get("gracePeriodSeconds"); gps != "" {
		v, err := strconv.ParseInt(gps, 10, 64)
		if err != nil {
			return opts, err
		}
		opts.GracePeriodSeconds = &v
	}
	if pp := q.Get("propagationPolicy"); pp != "" {
		switch pp {
		case string(metav1.DeletePropagationForeground),
			string(metav1.DeletePropagationBackground),
			string(metav1.DeletePropagationOrphan):
			policy := metav1.DeletionPropagation(pp)
			opts.PropagationPolicy = &policy
		default:
			return opts, errInvalidPropagationPolicy
		}
	}
	return opts, nil
}

var errInvalidPropagationPolicy = &deleteOptionsError{msg: "invalid propagationPolicy"}

type deleteOptionsError struct{ msg string }

func (e *deleteOptionsError) Error() string { return e.msg }

// Patch godoc
//
//	@Summary	Patch one resource (merge patch)
//	@Tags		resources
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/resources/{resource}/{name} [patch]
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name} [patch]
func (h *ResourceHandler) Patch(w http.ResponseWriter, r *http.Request) {
	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	if msg, bad := scopeMismatch(ref, r.PathValue("ns")); bad {
		writeError(w, http.StatusBadRequest, msg)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read body")
		return
	}
	obj, err := k8s.Patch(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), types.MergePatchType, body)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, obj.Object)
}

// Apply godoc
//
//	@Summary	Apply a YAML manifest (server-side apply)
//	@Tags		resources
//	@Accept		plain
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/resources [post]
func (h *ResourceHandler) Apply(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 4<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, "read body")
		return
	}
	obj, gvk, err := k8s.ParseManifest(body)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	mapping, err := restMappingWithRetry(b, gvk.GroupKind(), gvk.Version)
	if err != nil {
		h.fail(w, err)
		return
	}
	ref := k8s.ResourceRef{GVR: mapping.Resource, Namespaced: mapping.Scope.Name() == meta.RESTScopeNameNamespace}
	res, err := k8s.Apply(r.Context(), b.Dynamic, ref, obj)
	if err != nil {
		log.Printf("apply %s/%s: %v", ref.GVR.Resource, obj.GetName(), err)
		h.fail(w, err)
		return
	}
	writeStatus(w, http.StatusOK, res.Object)
}
