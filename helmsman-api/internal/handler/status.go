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
func (h *StatusHandler) Get(w http.ResponseWriter, _ *http.Request) {
	writeSuccess(w, h.provider.Status())
}
