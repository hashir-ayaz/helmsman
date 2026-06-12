package handler

import (
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
	writeSuccess(w, h.provider.Contexts())
}
