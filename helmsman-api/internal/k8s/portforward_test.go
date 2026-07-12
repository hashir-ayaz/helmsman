package k8s

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	discoveryv1 "k8s.io/api/discovery/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	fakek8s "k8s.io/client-go/kubernetes/fake"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

func TestResolveServicePortTarget_fromEndpoints(t *testing.T) {
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "web", Namespace: "default"},
		Spec: corev1.ServiceSpec{
			Ports: []corev1.ServicePort{{
				Port:       80,
				TargetPort: intstr.FromInt32(8080),
			}},
		},
	}
	ep := &corev1.Endpoints{
		ObjectMeta: metav1.ObjectMeta{Name: "web", Namespace: "default"},
		Subsets: []corev1.EndpointSubset{{
			Addresses: []corev1.EndpointAddress{{
				TargetRef: &corev1.ObjectReference{Kind: "Pod", Name: "pod-1"},
			}},
		}},
	}
	fake := fakek8s.NewSimpleClientset(svc, ep)
	b := &cluster.ClientBundle{Typed: fake}

	pod, port, err := ResolveServicePortTarget(context.Background(), b, "default", "web", 80)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pod != "pod-1" || port != 8080 {
		t.Fatalf("got pod=%q port=%d, want pod-1 8080", pod, port)
	}
}

func TestResolveServicePortTarget_noReadyEndpoints(t *testing.T) {
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "web", Namespace: "default"},
		Spec: corev1.ServiceSpec{
			Ports: []corev1.ServicePort{{Port: 80, TargetPort: intstr.FromInt32(8080)}},
		},
	}
	fake := fakek8s.NewSimpleClientset(svc)
	b := &cluster.ClientBundle{Typed: fake}

	_, _, err := ResolveServicePortTarget(context.Background(), b, "default", "web", 80)
	if err == nil {
		t.Fatal("expected error for missing endpoints")
	}
}

func TestResolveServicePortTarget_endpointSliceFallback(t *testing.T) {
	ready := true
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: "api", Namespace: "ns"},
		Spec: corev1.ServiceSpec{
			Ports: []corev1.ServicePort{{Port: 443, TargetPort: intstr.FromInt32(8443)}},
		},
	}
	slice := &discoveryv1.EndpointSlice{
		ObjectMeta: metav1.ObjectMeta{
			Name:      "api-slice",
			Namespace: "ns",
			Labels:    map[string]string{"kubernetes.io/service-name": "api"},
		},
		Endpoints: []discoveryv1.Endpoint{{
			Conditions: discoveryv1.EndpointConditions{Ready: &ready},
			TargetRef:  &corev1.ObjectReference{Kind: "Pod", Name: "api-pod"},
		}},
	}
	fake := fakek8s.NewSimpleClientset(svc, slice)
	b := &cluster.ClientBundle{Typed: fake}

	pod, port, err := ResolveServicePortTarget(context.Background(), b, "ns", "api", 443)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if pod != "api-pod" || port != 8443 {
		t.Fatalf("got pod=%q port=%d, want api-pod 8443", pod, port)
	}
}

func TestPortForwardManager_ListStopRemove(t *testing.T) {
	mgr := NewPortForwardManager()
	mgr.mu.Lock()
	live := &liveSession{
		meta: PortForwardSession{
			ID: "sess-1", Context: "ctx-a", Status: PortForwardStopped,
			Kind: PortForwardKindPod, Resource: "p", Namespace: "ns", Pod: "p",
			LocalPort: 20080, RemotePort: 80,
		},
		stopCh: make(chan struct{}),
		doneCh: make(chan struct{}),
	}
	close(live.doneCh)
	mgr.sessions["sess-1"] = &managedSession{live: live, stop: live.stopCh}
	mgr.mu.Unlock()

	list := mgr.List("ctx-a")
	if len(list) != 1 || list[0].ID != "sess-1" {
		t.Fatalf("list = %+v", list)
	}
	if err := mgr.Remove("ctx-a", "sess-1"); err != nil {
		t.Fatalf("remove: %v", err)
	}
	if len(mgr.List("ctx-a")) != 0 {
		t.Fatal("expected empty list after remove")
	}
}
