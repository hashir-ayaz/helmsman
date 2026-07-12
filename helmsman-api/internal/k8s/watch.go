package k8s

import (
	"context"
	"net/http"
	"time"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	watchpkg "k8s.io/apimachinery/pkg/watch"
)

// WatchEvent is the payload streamed to the frontend for each K8s watch event.
type WatchEvent struct {
	Type      string `json:"type"`
	Name      string `json:"name"`
	Namespace string `json:"namespace,omitempty"`
}

// Watch opens a K8s watch on the given resource and writes WatchEvent values to
// the returned channel. It reconnects automatically when the API server closes
// the watch. The channel is closed when ctx is cancelled.
func Watch(ctx context.Context, b *cluster.ClientBundle, ref ResourceRef, namespace string, opts ListOptions) (<-chan WatchEvent, error) {
	ch := make(chan WatchEvent, 64)
	go func() {
		defer close(ch)
		var resourceVersion string
		for {
			listOpts := metav1.ListOptions{
				ResourceVersion: resourceVersion,
			}
			if opts.LabelSelector != "" {
				listOpts.LabelSelector = opts.LabelSelector
			}
			if opts.FieldSelector != "" {
				listOpts.FieldSelector = opts.FieldSelector
			}
			watcher, err := dynResource(b.Dynamic, ref, namespace).Watch(ctx, listOpts)
			if err != nil {
				// Reconnect after back-off; avoids spinning on persistent errors.
				if !backoff(ctx) {
					return
				}
				continue
			}
		loop:
			for {
				select {
				case <-ctx.Done():
					watcher.Stop()
					return
				case event, ok := <-watcher.ResultChan():
					if !ok {
						break loop // server closed watch; reconnect
					}
					if event.Type == watchpkg.Error {
						// Only reset resourceVersion on 410 Gone.
						if status, ok := event.Object.(*metav1.Status); ok && status.Code == http.StatusGone {
							resourceVersion = ""
						}
						break loop
					}
					obj, ok := event.Object.(*unstructured.Unstructured)
					if !ok {
						continue
					}
					resourceVersion = obj.GetResourceVersion()
					we := WatchEvent{
						Type:      string(event.Type),
						Name:      obj.GetName(),
						Namespace: obj.GetNamespace(),
					}
					select {
					case ch <- we:
					case <-ctx.Done():
						watcher.Stop()
						return
					}
				}
			}
			watcher.Stop()
			if !backoff(ctx) {
				return
			}
		}
	}()
	return ch, nil
}

// backoff pauses 2 seconds or until ctx is cancelled; returns false if ctx fired.
func backoff(ctx context.Context) bool {
	select {
	case <-time.After(2 * time.Second):
		return true
	case <-ctx.Done():
		return false
	}
}
