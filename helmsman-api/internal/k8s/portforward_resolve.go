package k8s

import (
	"context"
	"fmt"
	"strconv"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

// ResolveServicePortTarget picks a ready pod and container port for a Service forward.
func ResolveServicePortTarget(
	ctx context.Context,
	b *cluster.ClientBundle,
	namespace, serviceName string,
	servicePort int,
) (podName string, targetPort int, err error) {
	svc, err := b.Typed.CoreV1().Services(namespace).Get(ctx, serviceName, metav1.GetOptions{})
	if err != nil {
		return "", 0, err
	}

	var sp *corev1.ServicePort
	for i := range svc.Spec.Ports {
		if int(svc.Spec.Ports[i].Port) == servicePort {
			sp = &svc.Spec.Ports[i]
			break
		}
	}
	if sp == nil {
		return "", 0, fmt.Errorf("service %s has no port %d", serviceName, servicePort)
	}

	targetPort, err = resolveTargetPort(sp)
	if err != nil {
		return "", 0, err
	}

	podName, err = pickReadyPodForService(ctx, b, namespace, svc)
	if err != nil {
		return "", 0, err
	}
	return podName, targetPort, nil
}

func resolveTargetPort(sp *corev1.ServicePort) (int, error) {
	switch sp.TargetPort.Type {
	case intstr.Int:
		if sp.TargetPort.IntVal <= 0 {
			return 0, fmt.Errorf("invalid target port on service port %d", sp.Port)
		}
		return int(sp.TargetPort.IntVal), nil
	case intstr.String:
		if sp.Port > 0 {
			return int(sp.Port), nil
		}
		return 0, fmt.Errorf("named target port %q requires pod inspection", sp.TargetPort.StrVal)
	default:
		if sp.Port > 0 {
			return int(sp.Port), nil
		}
		return 0, fmt.Errorf("could not resolve target port for service port %d", sp.Port)
	}
}

func pickReadyPodForService(ctx context.Context, b *cluster.ClientBundle, namespace string, svc *corev1.Service) (string, error) {
	ep, err := b.Typed.CoreV1().Endpoints(namespace).Get(ctx, svc.Name, metav1.GetOptions{})
	if err == nil {
		if name := firstReadyEndpointPod(ep); name != "" {
			return name, nil
		}
	} else if !apierrors.IsNotFound(err) {
		return "", err
	}

	// EndpointSlices fallback for clusters that no longer populate Endpoints.
	slices, err := b.Typed.DiscoveryV1().EndpointSlices(namespace).List(ctx, metav1.ListOptions{
		LabelSelector: fmt.Sprintf("kubernetes.io/service-name=%s", svc.Name),
	})
	if err != nil {
		return "", fmt.Errorf("no ready endpoints for service %s", svc.Name)
	}
	for _, slice := range slices.Items {
		for _, ep := range slice.Endpoints {
			if ep.Conditions.Ready != nil && !*ep.Conditions.Ready {
				continue
			}
			if ep.TargetRef != nil && ep.TargetRef.Kind == "Pod" && ep.TargetRef.Name != "" {
				return ep.TargetRef.Name, nil
			}
		}
	}
	return "", fmt.Errorf("no ready endpoints for service %s", svc.Name)
}

func firstReadyEndpointPod(ep *corev1.Endpoints) string {
	for _, subset := range ep.Subsets {
		for _, addr := range subset.Addresses {
			if addr.TargetRef != nil && addr.TargetRef.Kind == "Pod" && addr.TargetRef.Name != "" {
				return addr.TargetRef.Name
			}
			if addr.IP != "" && addr.Hostname != "" {
				return addr.Hostname
			}
		}
	}
	return ""
}

// ResolveNamedContainerPort looks up a container port by name on a pod.
func ResolveNamedContainerPort(ctx context.Context, b *cluster.ClientBundle, namespace, podName, portName string) (int, error) {
	pod, err := b.Typed.CoreV1().Pods(namespace).Get(ctx, podName, metav1.GetOptions{})
	if err != nil {
		return 0, err
	}
	for _, c := range append(pod.Spec.Containers, pod.Spec.InitContainers...) {
		for _, p := range c.Ports {
			if p.Name == portName {
				return int(p.ContainerPort), nil
			}
		}
	}
	// Allow numeric port names.
	if n, err := strconv.Atoi(portName); err == nil && n > 0 {
		return n, nil
	}
	return 0, fmt.Errorf("container port %q not found on pod %s", portName, podName)
}
