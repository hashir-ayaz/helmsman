package handler

import (
	"fmt"
	"net/http"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/runtime/schema"
)

// currentSentinel lets clients say "use the active context" without resolving it.
const currentSentinel = "_current"

// Handlers is the full handler set shared by the server.
type Handlers struct {
	Resources *ResourceHandler
	Actions   *ActionHandler
	Logs      *LogHandler
	Contexts  *ContextHandler
	Status    *StatusHandler
	Watch     *WatchHandler
	Rollout   *RolloutHandler
}

// New builds the handler set from a cluster provider.
func New(p cluster.Provider) Handlers {
	return Handlers{
		Resources: &ResourceHandler{provider: p},
		Actions:   &ActionHandler{provider: p},
		Logs:      &LogHandler{provider: p},
		Contexts:  &ContextHandler{provider: p},
		Status:    &StatusHandler{provider: p},
		Watch:     &WatchHandler{provider: p},
		Rollout:   &RolloutHandler{provider: p},
	}
}

// bundleAndRef resolves the context bundle and the resource ref from the request.
func bundleAndRef(p cluster.Provider, r *http.Request) (*cluster.ClientBundle, k8s.ResourceRef, error) {
	b, err := bundleFor(p, r)
	if err != nil {
		return nil, k8s.ResourceRef{}, err
	}
	ref, err := resolveRef(b, r.PathValue("resource"))
	if err != nil {
		return nil, k8s.ResourceRef{}, err
	}
	return b, ref, nil
}

// resolveRef resolves a URL resource identifier, resetting discovery once on NoMatch.
func resolveRef(b *cluster.ClientBundle, resource string) (k8s.ResourceRef, error) {
	ref, err := k8s.Resolve(b.Mapper, resource)
	if err != nil && meta.IsNoMatchError(err) {
		b.ResetMapper()
		ref, err = k8s.Resolve(b.Mapper, resource)
	}
	return ref, err
}

// restMappingWithRetry resolves GVK to RESTMapping, resetting discovery once on NoMatch.
func restMappingWithRetry(b *cluster.ClientBundle, gk schema.GroupKind, version string) (*meta.RESTMapping, error) {
	mapping, err := b.Mapper.RESTMapping(gk, version)
	if err != nil && meta.IsNoMatchError(err) {
		b.ResetMapper()
		mapping, err = b.Mapper.RESTMapping(gk, version)
	}
	return mapping, err
}

// scopeMismatch returns a client message when ns and resource scope disagree.
func scopeMismatch(ref k8s.ResourceRef, ns string) (string, bool) {
	switch {
	case ref.Namespaced && ns == "":
		return fmt.Sprintf("%s is namespaced; specify a namespace", ref.GVR.Resource), true
	case !ref.Namespaced && ns != "":
		return fmt.Sprintf("%s is cluster-scoped; do not specify a namespace", ref.GVR.Resource), true
	}
	return "", false
}

func bundleFor(p cluster.Provider, r *http.Request) (*cluster.ClientBundle, error) {
	if st := p.Status(); !st.Ready {
		return nil, &cluster.NotReadyError{Status: st}
	}
	ctxName := r.PathValue("ctx")
	if ctxName == currentSentinel {
		ctxName = ""
	}
	return p.Bundle(ctxName)
}

// Recoverer converts panics into 500s so one bad request can't crash the server.
func Recoverer(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				writeError(w, http.StatusInternalServerError, "internal error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}
