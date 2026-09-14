package handler

import (
	"fmt"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

type ContextHandler struct{ provider cluster.Provider }

// List godoc
//
//	@Summary	List kubeconfig contexts
//	@Tags		contexts
//	@Produce	json
//	@Success	200	{object}	APIResponse{data=[]cluster.ContextInfo}
//	@Router		/api/v1/contexts [get]
func (h *ContextHandler) List(w http.ResponseWriter, _ *http.Request) {
	if st := h.provider.Status(); !st.Ready {
		writeErrorCode(w, http.StatusServiceUnavailable, st.Code, st.Message)
		return
	}
	writeSuccess(w, h.provider.Contexts())
}

// Status godoc
//
//	@Summary	Probe one kubeconfig context
//	@Tags		contexts
//	@Produce	json
//	@Param		ctx	path		string	true	"Context name, or _current for the active context"
//	@Success	200	{object}	APIResponse{data=cluster.Status}
//	@Failure	404	{object}	APIResponse
//	@Failure	503	{object}	APIResponse
//	@Router		/api/v1/contexts/{ctx}/status [get]
func (h *ContextHandler) Status(w http.ResponseWriter, r *http.Request) {
	if st := h.provider.Status(); !st.Ready {
		writeErrorCode(w, http.StatusServiceUnavailable, st.Code, st.Message)
		return
	}
	name := r.PathValue("ctx")
	if name == currentSentinel {
		name = ""
	}
	// Validate before probing: Probe("bogus") would otherwise surface as a
	// misleading cluster_unreachable.
	if name != "" && !h.hasContext(name) {
		writeErrorCode(w, http.StatusNotFound, "context_not_found",
			fmt.Sprintf("No context named %q in your kubeconfig.", name))
		return
	}
	writeSuccess(w, h.provider.Probe(r.Context(), name))
}

func (h *ContextHandler) hasContext(name string) bool {
	for _, c := range h.provider.Contexts() {
		if c.Name == name {
			return true
		}
	}
	return false
}
