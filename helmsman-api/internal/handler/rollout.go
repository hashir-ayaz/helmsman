package handler

import (
	"encoding/json"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"
)

type RolloutHandler struct{ provider cluster.Provider }

// History godoc
//
//	@Summary	List rollout revision history for a workload
//	@Tags		rollout
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/history [get]
func (h *RolloutHandler) History(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	entries, err := k8s.RolloutHistory(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"))
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	writeSuccess(w, entries)
}

type undoRequest struct {
	ToRevision int64 `json:"toRevision"`
}

// Undo godoc
//
//	@Summary	Roll back to a previous revision (toRevision=0 means previous)
//	@Tags		rollout
//	@Accept		json
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/undo [post]
func (h *RolloutHandler) Undo(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	var body undoRequest
	_ = json.NewDecoder(r.Body).Decode(&body)

	if err := k8s.RolloutUndo(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name"), body.ToRevision); err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	writeSuccess(w, map[string]any{"rolled_back": r.PathValue("name"), "toRevision": body.ToRevision})
}

// Pause godoc
//
//	@Summary	Pause a Deployment rollout (sets spec.paused=true)
//	@Tags		rollout
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/pause [post]
func (h *RolloutHandler) Pause(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	if err := k8s.RolloutPause(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name")); err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	writeSuccess(w, map[string]string{"paused": r.PathValue("name")})
}

// Resume godoc
//
//	@Summary	Resume a paused Deployment rollout (sets spec.paused=false)
//	@Tags		rollout
//	@Produce	json
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/resume [post]
func (h *RolloutHandler) Resume(w http.ResponseWriter, r *http.Request) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	ref, err := resolveRef(b, r.PathValue("workload"))
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	if err := k8s.RolloutResume(r.Context(), b.Dynamic, ref, r.PathValue("ns"), r.PathValue("name")); err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	writeSuccess(w, map[string]string{"resumed": r.PathValue("name")})
}
