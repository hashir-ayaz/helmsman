package handler

import (
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

type StatusHandler struct{ provider cluster.Provider }

// Get godoc
//
//	@Summary	Cluster readiness status
//	@Tags		status
//	@Produce	json
//	@Success	200	{object}	APIResponse{data=cluster.Status}
//	@Router		/api/v1/status [get]
func (h *StatusHandler) Get(w http.ResponseWriter, r *http.Request) {
	st := h.provider.Status()
	if !st.Ready {
		writeSuccess(w, st)
		return
	}
	writeSuccess(w, h.provider.Probe(r.Context(), ""))
}
