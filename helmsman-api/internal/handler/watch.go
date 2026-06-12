package handler

import (
	"encoding/json"
	"fmt"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"
)

type WatchHandler struct{ provider cluster.Provider }

// Stream opens a K8s watch and streams events as SSE.
//
//	@Summary	Watch resources (SSE)
//	@Tags		watch
//	@Produce	text/event-stream
//	@Router		/api/v1/contexts/{ctx}/resources/{resource}/watch [get]
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/watch [get]
func (h *WatchHandler) Stream(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming unsupported")
		return
	}

	b, ref, err := bundleAndRef(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}

	ns := r.PathValue("ns")
	if msg, mismatch := scopeMismatch(ref, ns); mismatch {
		writeError(w, http.StatusBadRequest, msg)
		return
	}

	ch, err := k8s.Watch(r.Context(), b, ref, ns)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)
	flusher.Flush()

	for event := range ch {
		data, err := json.Marshal(event)
		if err != nil {
			fmt.Fprintf(w, "event: error\ndata: marshal failure\n\n")
			flusher.Flush()
			return
		}
		fmt.Fprintf(w, "data: %s\n\n", data)
		flusher.Flush()
	}
}
