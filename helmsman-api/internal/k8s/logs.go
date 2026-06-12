package k8s

import (
	"context"
	"io"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"

	corev1 "k8s.io/api/core/v1"
)

// LogOptions are the pod log stream parameters.
type LogOptions struct {
	Container string
	Follow    bool
	Previous  bool
	TailLines *int64
}

// OpenLogStream returns a reader over a pod's logs. The caller must Close it.
func OpenLogStream(ctx context.Context, b *cluster.ClientBundle, namespace, pod string, opts LogOptions) (io.ReadCloser, error) {
	req := b.Typed.CoreV1().Pods(namespace).GetLogs(pod, &corev1.PodLogOptions{
		Container: opts.Container,
		Follow:    opts.Follow,
		Previous:  opts.Previous,
		TailLines: opts.TailLines,
	})
	return req.Stream(ctx)
}
