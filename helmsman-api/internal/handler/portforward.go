package handler

import (
	"encoding/json"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"
)

// PortForwardHandler manages port-forward session lifecycle.
type PortForwardHandler struct {
	provider cluster.Provider
	manager  *k8s.PortForwardManager
}

func (h *PortForwardHandler) fail(w http.ResponseWriter, err error) {
	code, msg := statusFromK8sErr(err)
	writeError(w, code, msg)
}

func (h *PortForwardHandler) contextName(r *http.Request) string {
	ctxName := r.PathValue("ctx")
	if ctxName == currentSentinel {
		return h.provider.Current()
	}
	return ctxName
}

// StartPod begins a port-forward to a pod.
func (h *PortForwardHandler) StartPod(w http.ResponseWriter, r *http.Request) {
	h.start(w, r, k8s.PortForwardKindPod, r.PathValue("name"), r.PathValue("name"))
}

// StartService begins a port-forward to a service (resolves a backing pod).
func (h *PortForwardHandler) StartService(w http.ResponseWriter, r *http.Request) {
	h.start(w, r, k8s.PortForwardKindService, r.PathValue("name"), "")
}

func (h *PortForwardHandler) start(w http.ResponseWriter, r *http.Request, kind k8s.PortForwardKind, resource, podOverride string) {
	b, err := bundleFor(h.provider, r)
	if err != nil {
		h.fail(w, err)
		return
	}
	var body k8s.PortForwardStartRequest
	if err := json.NewDecoder(r.Body).Decode(&body); err != nil {
		writeError(w, http.StatusBadRequest, "invalid port-forward request")
		return
	}
	if body.RemotePort <= 0 {
		writeError(w, http.StatusBadRequest, "remotePort must be > 0")
		return
	}

	ctxName := h.contextName(r)
	ns := r.PathValue("ns")

	var session *k8s.PortForwardSession
	switch kind {
	case k8s.PortForwardKindPod:
		pod := resource
		if podOverride != "" {
			pod = podOverride
		}
		session, err = k8s.StartPodPortForward(r.Context(), h.manager, b, ctxName, ns, pod, resource, kind, body)
	case k8s.PortForwardKindService:
		session, err = k8s.StartServicePortForward(r.Context(), h.manager, b, ctxName, ns, resource, body)
	default:
		writeError(w, http.StatusBadRequest, "unsupported kind")
		return
	}
	if err != nil {
		h.failPlain(w, err)
		return
	}
	writeStatus(w, http.StatusCreated, session)
}

func (h *PortForwardHandler) failPlain(w http.ResponseWriter, err error) {
	if _, ok := err.(*cluster.NotReadyError); ok {
		h.fail(w, err)
		return
	}
	writeError(w, http.StatusBadRequest, err.Error())
}

// List returns all port-forward sessions for the context.
func (h *PortForwardHandler) List(w http.ResponseWriter, r *http.Request) {
	if st := h.provider.Status(); !st.Ready {
		h.fail(w, &cluster.NotReadyError{Status: st})
		return
	}
	ctxName := h.contextName(r)
	writeSuccess(w, h.manager.List(ctxName))
}

// Stop terminates an active port-forward session.
func (h *PortForwardHandler) Stop(w http.ResponseWriter, r *http.Request) {
	if st := h.provider.Status(); !st.Ready {
		h.fail(w, &cluster.NotReadyError{Status: st})
		return
	}
	ctxName := h.contextName(r)
	id := r.PathValue("id")
	session, err := h.manager.Stop(ctxName, id)
	if err != nil {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	writeSuccess(w, session)
}

// Remove deletes a stopped or lost port-forward session record.
func (h *PortForwardHandler) Remove(w http.ResponseWriter, r *http.Request) {
	if st := h.provider.Status(); !st.Ready {
		h.fail(w, &cluster.NotReadyError{Status: st})
		return
	}
	ctxName := h.contextName(r)
	id := r.PathValue("id")
	if err := h.manager.Remove(ctxName, id); err != nil {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	writeSuccess(w, map[string]string{"id": id})
}
