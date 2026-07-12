package k8s

import (
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/httpstream"
	"k8s.io/apimachinery/pkg/util/intstr"
	"k8s.io/apimachinery/pkg/util/runtime"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/portforward"
	"k8s.io/client-go/transport/spdy"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

func podPortForwardURL(restConfig *rest.Config, namespace, podName string) (*url.URL, error) {
	host := restConfig.Host
	if host == "" {
		return nil, fmt.Errorf("rest config has no host")
	}
	path := fmt.Sprintf("/api/v1/namespaces/%s/pods/%s/portforward", namespace, podName)
	u, err := url.Parse(host)
	if err != nil {
		return nil, err
	}
	u.Path = path
	return u, nil
}

func newPortForwardDialer(restConfig *rest.Config, reqURL *url.URL) (httpstream.Dialer, error) {
	transport, upgrader, err := spdy.RoundTripperFor(restConfig)
	if err != nil {
		return nil, err
	}
	spdyDialer := spdy.NewDialer(upgrader, &http.Client{Transport: transport}, http.MethodPost, reqURL)
	wsDialer, err := portforward.NewSPDYOverWebsocketDialer(reqURL, restConfig)
	if err != nil {
		return spdyDialer, nil
	}
	return portforward.NewFallbackDialer(wsDialer, spdyDialer, func(err error) bool {
		return httpstream.IsUpgradeFailure(err) || httpstream.IsHTTPSProxyError(err)
	}), nil
}

type countingPortForwarder struct {
	dialer     httpstream.Dialer
	localPort  int
	remotePort int
	stats      *sessionStats
	stopCh     <-chan struct{}
	readyCh    chan struct{}
}

func (cpf *countingPortForwarder) run() error {
	streamConn, protocol, err := cpf.dialer.Dial(portforward.PortForwardProtocolV1Name)
	if err != nil {
		return fmt.Errorf("error upgrading connection: %w", err)
	}
	defer streamConn.Close()
	if protocol != portforward.PortForwardProtocolV1Name {
		return fmt.Errorf("unable to negotiate protocol: client supports %q, server returned %q",
			portforward.PortForwardProtocolV1Name, protocol)
	}

	listener, err := net.Listen("tcp4", net.JoinHostPort("127.0.0.1", strconv.Itoa(cpf.localPort)))
	if err != nil {
		return fmt.Errorf("unable to listen on port %d: %w", cpf.localPort, err)
	}
	defer listener.Close()

	_, portStr, _ := net.SplitHostPort(listener.Addr().String())
	actualLocal, _ := strconv.Atoi(portStr)
	cpf.localPort = actualLocal

	close(cpf.readyCh)

	go cpf.acceptLoop(listener, streamConn, uint16(cpf.remotePort))

	select {
	case <-cpf.stopCh:
	case <-streamConn.CloseChan():
		return portforward.ErrLostConnectionToPod
	}
	return nil
}

func (cpf *countingPortForwarder) acceptLoop(listener net.Listener, streamConn httpstream.Connection, remotePort uint16) {
	networkClosed := "use of closed network connection"
	for {
		select {
		case <-streamConn.CloseChan():
			return
		case <-cpf.stopCh:
			return
		default:
			conn, err := listener.Accept()
			if err != nil {
				if !strings.Contains(strings.ToLower(err.Error()), networkClosed) {
					runtime.HandleError(fmt.Errorf("accept: %w", err))
				}
				return
			}
			go cpf.handleConnection(wrapCountingConn(conn, cpf.stats), streamConn, remotePort)
		}
	}
}

func (cpf *countingPortForwarder) handleConnection(conn net.Conn, streamConn httpstream.Connection, remotePort uint16) {
	defer conn.Close()
	defer releaseCountingConn(cpf.stats)

	requestID := 1
	headers := http.Header{}
	headers.Set(corev1.StreamType, corev1.StreamTypeError)
	headers.Set(corev1.PortHeader, fmt.Sprintf("%d", remotePort))
	headers.Set(corev1.PortForwardRequestIDHeader, strconv.Itoa(requestID))
	errorStream, err := streamConn.CreateStream(headers)
	if err != nil {
		return
	}
	errorStream.Close()

	errorChan := make(chan error, 1)
	go func() {
		message, readErr := io.ReadAll(errorStream)
		switch {
		case readErr != nil:
			errorChan <- readErr
		case len(message) > 0:
			errorChan <- fmt.Errorf("%s", string(message))
		}
		close(errorChan)
	}()

	headers.Set(corev1.StreamType, corev1.StreamTypeData)
	dataStream, err := streamConn.CreateStream(headers)
	if err != nil {
		return
	}
	defer streamConn.RemoveStreams(dataStream)

	localDone := make(chan struct{})
	remoteDone := make(chan struct{})

	go func() {
		_, _ = io.Copy(conn, dataStream)
		close(remoteDone)
	}()

	go func() {
		defer dataStream.Close()
		if _, err := io.Copy(dataStream, conn); err != nil {
			close(localDone)
		}
	}()

	select {
	case <-remoteDone:
	case <-localDone:
	}

	_ = dataStream.Reset()
	if err := <-errorChan; err != nil {
		streamConn.Close()
	}
}

func startCountingPortForward(
	b *cluster.ClientBundle,
	namespace, podName string,
	localPort, remotePort int,
	stats *sessionStats,
) (actualLocal int, stopCh chan struct{}, doneCh chan struct{}, err error) {
	if b.Config == nil {
		return 0, nil, nil, fmt.Errorf("rest config not available")
	}
	reqURL, err := podPortForwardURL(b.Config, namespace, podName)
	if err != nil {
		return 0, nil, nil, err
	}
	dialer, err := newPortForwardDialer(b.Config, reqURL)
	if err != nil {
		return 0, nil, nil, err
	}

	stopCh = make(chan struct{})
	readyCh := make(chan struct{})
	doneCh = make(chan struct{})

	cpf := &countingPortForwarder{
		dialer:     dialer,
		localPort:  localPort,
		remotePort: remotePort,
		stats:      stats,
		stopCh:     stopCh,
		readyCh:    readyCh,
	}

	go func() {
		defer close(doneCh)
		_ = cpf.run()
	}()

	select {
	case <-readyCh:
		return cpf.localPort, stopCh, doneCh, nil
	case <-time.After(30 * time.Second):
		close(stopCh)
		return 0, nil, nil, fmt.Errorf("timed out waiting for port-forward listeners")
	}
}

// StartPodPortForward begins forwarding to a pod and returns the session snapshot.
func StartPodPortForward(
	ctx context.Context,
	mgr *PortForwardManager,
	b *cluster.ClientBundle,
	contextName, namespace, podName, resourceName string,
	kind PortForwardKind,
	req PortForwardStartRequest,
) (*PortForwardSession, error) {
	if req.RemotePort <= 0 {
		return nil, fmt.Errorf("remotePort must be > 0")
	}
	return mgr.start(ctx, b, startParams{
		contextName: contextName,
		namespace:   namespace,
		kind:        kind,
		resource:    resourceName,
		pod:         podName,
		localPort:   req.LocalPort,
		remotePort:  req.RemotePort,
		container:   req.Container,
	})
}

// StartServicePortForward resolves a service endpoint and begins forwarding.
func StartServicePortForward(
	ctx context.Context,
	mgr *PortForwardManager,
	b *cluster.ClientBundle,
	contextName, namespace, serviceName string,
	req PortForwardStartRequest,
) (*PortForwardSession, error) {
	if req.RemotePort <= 0 {
		return nil, fmt.Errorf("remotePort must be > 0")
	}
	podName, targetPort, err := ResolveServicePortTarget(ctx, b, namespace, serviceName, req.RemotePort)
	if err != nil {
		return nil, err
	}
	svc, err := b.Typed.CoreV1().Services(namespace).Get(ctx, serviceName, metav1.GetOptions{})
	if err == nil {
		for _, sp := range svc.Spec.Ports {
			if int(sp.Port) == req.RemotePort && sp.TargetPort.Type == intstr.String {
				if named, err := ResolveNamedContainerPort(ctx, b, namespace, podName, sp.TargetPort.StrVal); err == nil {
					targetPort = named
				}
			}
		}
	}
	return mgr.start(ctx, b, startParams{
		contextName: contextName,
		namespace:   namespace,
		kind:        PortForwardKindService,
		resource:    serviceName,
		pod:         podName,
		localPort:   req.LocalPort,
		remotePort:  targetPort,
		container:   req.Container,
	})
}
