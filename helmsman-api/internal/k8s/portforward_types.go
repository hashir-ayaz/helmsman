package k8s

import "time"

// PortForwardStatus is the lifecycle state of a port-forward session.
type PortForwardStatus string

const (
	PortForwardActive  PortForwardStatus = "active"
	PortForwardStopped PortForwardStatus = "stopped"
	PortForwardLost    PortForwardStatus = "lost"
	PortForwardError   PortForwardStatus = "error"
)

// PortForwardKind identifies the user-facing resource that initiated the forward.
type PortForwardKind string

const (
	PortForwardKindPod     PortForwardKind = "Pod"
	PortForwardKindService PortForwardKind = "Service"
)

// PortForwardSession is the API-facing view of a port-forward session.
type PortForwardSession struct {
	ID            string            `json:"id"`
	Context       string            `json:"context"`
	Kind          PortForwardKind   `json:"kind"`
	Resource      string            `json:"resource"`
	Namespace     string            `json:"namespace"`
	Pod           string            `json:"pod"`
	LocalPort     int               `json:"localPort"`
	RemotePort    int               `json:"remotePort"`
	Container     string            `json:"container,omitempty"`
	Status        PortForwardStatus `json:"status"`
	Connections   int               `json:"connections"`
	BytesSent     int64             `json:"bytesSent"`
	BytesReceived int64             `json:"bytesReceived"`
	Error         string            `json:"error,omitempty"`
	StartedAt     time.Time         `json:"startedAt"`
}

// PortForwardStartRequest is the body for starting a port-forward.
type PortForwardStartRequest struct {
	LocalPort  int    `json:"localPort"`
	RemotePort int    `json:"remotePort"`
	Container  string `json:"container,omitempty"`
}
