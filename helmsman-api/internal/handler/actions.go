package handler

import (
	"encoding/json"
	"net/http"

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
//	@Summary	Scale a workload
//	@Tags		actions
//	@Accept		json
//	@Produce	json
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
	ref, err := resolveRef(b, "deployments")
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
