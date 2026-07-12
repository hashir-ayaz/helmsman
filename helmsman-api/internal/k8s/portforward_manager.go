package k8s

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"
	"time"

	"github.com/google/uuid"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

// PortForwardManager tracks active and historical port-forward sessions.
type PortForwardManager struct {
	mu       sync.RWMutex
	sessions map[string]*managedSession
}

type managedSession struct {
	live *liveSession
	stop chan struct{}
}

type liveSession struct {
	meta    PortForwardSession
	stats   sessionStats
	stopCh  chan struct{}
	doneCh  chan struct{}
	stopped atomic.Bool
	mu      sync.Mutex
}

type startParams struct {
	contextName string
	namespace   string
	kind        PortForwardKind
	resource    string
	pod         string
	localPort   int
	remotePort  int
	container   string
}

// NewPortForwardManager creates an empty session registry.
func NewPortForwardManager() *PortForwardManager {
	return &PortForwardManager{sessions: map[string]*managedSession{}}
}

var defaultManager = NewPortForwardManager()

// DefaultPortForwardManager returns the process-wide port-forward registry.
func DefaultPortForwardManager() *PortForwardManager { return defaultManager }

func (s *liveSession) view() PortForwardSession {
	s.mu.Lock()
	defer s.mu.Unlock()
	conns, sent, recv := s.stats.snapshot()
	out := s.meta
	out.Connections = conns
	out.BytesSent = sent
	out.BytesReceived = recv
	return out
}

func (s *liveSession) setStatus(status PortForwardStatus, errMsg string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.meta.Status = status
	s.meta.Error = errMsg
}

func (m *PortForwardManager) start(_ context.Context, b *cluster.ClientBundle, p startParams) (*PortForwardSession, error) {
	id := uuid.NewString()
	live := &liveSession{
		meta: PortForwardSession{
			ID:         id,
			Context:    p.contextName,
			Kind:       p.kind,
			Resource:   p.resource,
			Namespace:  p.namespace,
			Pod:        p.pod,
			LocalPort:  p.localPort,
			RemotePort: p.remotePort,
			Container:  p.container,
			Status:     PortForwardActive,
			StartedAt:  time.Now().UTC(),
		},
	}

	actualLocal, stopCh, doneCh, err := startCountingPortForward(
		b, p.namespace, p.pod, p.localPort, p.remotePort, &live.stats,
	)
	if err != nil {
		return nil, err
	}
	live.meta.LocalPort = actualLocal
	live.stopCh = stopCh
	live.doneCh = doneCh

	go func() {
		<-doneCh
		if live.stopped.Load() {
			live.setStatus(PortForwardStopped, "")
		} else {
			live.setStatus(PortForwardLost, "lost connection to pod")
		}
	}()

	m.mu.Lock()
	m.sessions[id] = &managedSession{live: live, stop: stopCh}
	m.mu.Unlock()

	view := live.view()
	return &view, nil
}

// List returns all sessions for a context, newest first.
func (m *PortForwardManager) List(contextName string) []PortForwardSession {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]PortForwardSession, 0)
	for _, ms := range m.sessions {
		view := ms.live.view()
		if view.Context != contextName {
			continue
		}
		out = append(out, view)
	}
	// newest first
	for i := 0; i < len(out); i++ {
		for j := i + 1; j < len(out); j++ {
			if out[j].StartedAt.After(out[i].StartedAt) {
				out[i], out[j] = out[j], out[i]
			}
		}
	}
	return out
}

// Stop terminates an active session but keeps the record.
func (m *PortForwardManager) Stop(contextName, id string) (*PortForwardSession, error) {
	ms, err := m.get(contextName, id)
	if err != nil {
		return nil, err
	}
	view := ms.live.view()
	if view.Status != PortForwardActive {
		return &view, nil
	}
	ms.live.stopped.Store(true)
	close(ms.stop)
	<-ms.live.doneCh
	ms.live.setStatus(PortForwardStopped, "")
	view = ms.live.view()
	return &view, nil
}

// Remove deletes a stopped or lost session.
func (m *PortForwardManager) Remove(contextName, id string) error {
	ms, err := m.get(contextName, id)
	if err != nil {
		return err
	}
	view := ms.live.view()
	if view.Status == PortForwardActive {
		if _, err := m.Stop(contextName, id); err != nil {
			return err
		}
	}
	m.mu.Lock()
	delete(m.sessions, id)
	m.mu.Unlock()
	return nil
}

// StopAll stops every active session during shutdown.
func (m *PortForwardManager) StopAll() {
	m.mu.RLock()
	all := make([]*managedSession, 0, len(m.sessions))
	for _, ms := range m.sessions {
		all = append(all, ms)
	}
	m.mu.RUnlock()

	for _, ms := range all {
		view := ms.live.view()
		if view.Status == PortForwardActive {
			close(ms.stop)
		}
	}
}

func (m *PortForwardManager) get(contextName, id string) (*managedSession, error) {
	m.mu.RLock()
	ms, ok := m.sessions[id]
	m.mu.RUnlock()
	if !ok {
		return nil, fmt.Errorf("port-forward session %q not found", id)
	}
	view := ms.live.view()
	if view.Context != contextName {
		return nil, fmt.Errorf("port-forward session %q not found", id)
	}
	return ms, nil
}
