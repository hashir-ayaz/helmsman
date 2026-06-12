package handler

import (
	"bufio"
	"net/http"
	"strconv"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"
)

type LogHandler struct{ provider cluster.Provider }

// Stream godoc
//
//	@Summary	Stream pod logs (SSE)
//	@Tags		logs
//	@Produce	text/event-stream
//	@Router		/api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log [get]
func (h *LogHandler) Stream(w http.ResponseWriter, r *http.Request) {
	flusher, ok := w.(http.Flusher)
	if !ok {
		writeError(w, http.StatusInternalServerError, "streaming unsupported")
		return
	}
	b, err := bundleFor(h.provider, r)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}

	opts := k8s.LogOptions{
		Container: r.URL.Query().Get("container"),
		Follow:    r.URL.Query().Get("follow") == "true",
		Previous:  r.URL.Query().Get("previous") == "true",
	}
	if tl := r.URL.Query().Get("tailLines"); tl != "" {
		if n, convErr := strconv.ParseInt(tl, 10, 64); convErr == nil {
			opts.TailLines = &n
		}
	}

	stream, err := k8s.OpenLogStream(r.Context(), b, r.PathValue("ns"), r.PathValue("name"), opts)
	if err != nil {
		code, msg := statusFromK8sErr(err)
		writeError(w, code, msg)
		return
	}
	defer stream.Close()

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.WriteHeader(http.StatusOK)

	scanner := bufio.NewScanner(stream)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	for scanner.Scan() {
		select {
		case <-r.Context().Done():
			return
		default:
		}
		w.Write([]byte("data: "))
		w.Write(scanner.Bytes())
		w.Write([]byte("\n\n"))
		flusher.Flush()
	}
}
