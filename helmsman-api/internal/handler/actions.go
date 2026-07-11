package handler

import (
	"encoding/json"
	"net/http"

	"k8s.io/apimachinery/pkg/api/resource"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"
)

type ActionHandler struct{ provider cluster.Provider }

func (h *ActionHandler) fail(w http.ResponseWriter, err error) {
	code, msg := statusFromK8sErr(err)
	writeError(w, code, msg)
}

type scaleRequest struct {
	Replicas int32 `json:"replicas"`
}

// Scale godoc
//
//	@Summary	Scale a workload (deployments, statefulsets, replicasets)
//	@Tags		actions
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/scale [post]
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/deployments/{name}/scale [post]
func (h *ActionHandler) Scale(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body scaleRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid scale request")
		return
	}
	// PathValue returns "" when matched by the literal deployments/{name}/scale route.
	workload := r.PathValue("workload")
	if workload == "" {
		workload = "deployments"
	}
	ref, err := resolveRef(b, workload)
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.Scale(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), body.Replicas); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]any{"name": r.PathValue("name"), "replicas": body.Replicas})
}

type restartRequest struct {
	RestartedAt string `json:"restartedAt"`
}

// Restart godoc
//
//	@Summary	Rollout restart a workload
//	@Tags		actions
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/restart [post]
func (h *ActionHandler) Restart(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body restartRequest
	_ = json.NewDecoder(r.Body).Decode(&body)
	if body.RestartedAt == "" {
		writeError(w, http.StatusBadRequest, "restartedAt is required")
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.Restart(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), body.RestartedAt); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"restarted": r.PathValue("name")})
}

// Suspend godoc
//
//	@Summary	Suspend a CronJob or Job (sets spec.suspend=true)
//	@Tags		actions
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/suspend [post]
func (h *ActionHandler) Suspend(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.SetSuspend(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), true); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"suspended": r.PathValue("name")})
}

// Resume godoc
//
//	@Summary	Resume a suspended CronJob or Job (sets spec.suspend=false)
//	@Tags		actions
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/resume [post]
func (h *ActionHandler) Resume(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.SetSuspend(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), false); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"resumed": r.PathValue("name")})
}

// CancelJob godoc
//
//	@Summary	Cancel a Job: suspend it and delete its running pods
//	@Tags		actions
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/jobs/{name}/cancel [post]
func (h *ActionHandler) CancelJob(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	ref, err := resolveRef(b, "jobs")
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.CancelJob(r.Context(), b, ref, r.PathValue("ns"), r.PathValue("name")); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]string{"cancelled": r.PathValue("name")})
}

type resizePVCRequest struct {
	Storage string `json:"storage"`
}

// ResizePVC godoc
//
//	@Summary	Resize a PersistentVolumeClaim (increase storage request)
//	@Tags		actions
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/persistentvolumeclaims/{name}/resize [post]
func (h *ActionHandler) ResizePVC(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body resizePVCRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid resize request")
		return
	}
	if body.Storage == "" {
		writeError(w, http.StatusBadRequest, "storage is required")
		return
	}
	qty, err := resource.ParseQuantity(body.Storage)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid storage quantity")
		return
	}
	storage := qty.String()

	ref, err := resolveRef(b, "persistentvolumeclaims")
	if err != nil {
		h.fail(w, err)
		return
	}
	if err := k8s.ResizePVC(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), storage); err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, map[string]any{"name": r.PathValue("name"), "storage": storage})
}

type drainRequest struct {
	GracePeriodSeconds *int64 `json:"gracePeriodSeconds"`
}

// DrainNode godoc
//
//	@Summary	Drain a node: cordon + evict non-daemonset pods
//	@Tags		actions
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/nodes/{name}/drain [post]
func (h *ActionHandler) DrainNode(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body drainRequest
	_ = json.NewDecoder(r.Body).Decode(&body)

	result, err := k8s.DrainNode(r.Context(), b, r.PathValue("name"), body.GracePeriodSeconds)
	if err != nil {
		h.fail(w, err)
		return
	}
	writeSuccess(w, result)
}
