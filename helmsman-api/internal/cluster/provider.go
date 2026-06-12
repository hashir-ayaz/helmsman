// Package cluster manages Kubernetes client connections, one bundle per
// kubeconfig context, built lazily and cached.
package cluster

import (
	"fmt"
	"sync"

	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/client-go/discovery"
	memory "k8s.io/client-go/discovery/cached/memory"
	"k8s.io/client-go/dynamic"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/restmapper"
	"k8s.io/client-go/tools/clientcmd"
)

// ClientBundle holds every client a handler needs for one cluster context.
type ClientBundle struct {
	Typed     kubernetes.Interface
	Dynamic   dynamic.Interface
	Discovery discovery.DiscoveryInterface
	Mapper    meta.RESTMapper
}

// ResetMapper invalidates cached discovery so newly installed CRDs resolve.
func (b *ClientBundle) ResetMapper() {
	if m, ok := b.Mapper.(interface{ Reset() }); ok {
		m.Reset()
	}
}

// ContextInfo describes a selectable kubeconfig context for the UI.
type ContextInfo struct {
	Name      string `json:"name"`
	Cluster   string `json:"cluster"`
	Namespace string `json:"namespace"`
	IsCurrent bool   `json:"isCurrent"`
}

// Provider enumerates contexts and supplies cached client bundles.
type Provider interface {
	Contexts() []ContextInfo
	Current() string
	Bundle(contextName string) (*ClientBundle, error)
}

type kubeProvider struct {
	raw     clientcmd.ClientConfig
	current string
	infos   []ContextInfo
	loader  clientcmd.ClientConfigLoadingRules

	mu    sync.RWMutex
	cache map[string]*ClientBundle
}

// NewProvider loads the kubeconfig at path (honouring $KUBECONFIG merge rules
// when path is empty) and prepares lazy per-context bundles.
func NewProvider(kubeconfigPath string) (Provider, error) {
	rules := clientcmd.NewDefaultClientConfigLoadingRules()
	if kubeconfigPath != "" {
		rules.ExplicitPath = kubeconfigPath
	}
	cfg, err := rules.Load()
	if err != nil {
		return nil, fmt.Errorf("load kubeconfig: %w", err)
	}

	infos := make([]ContextInfo, 0, len(cfg.Contexts))
	for name, c := range cfg.Contexts {
		infos = append(infos, ContextInfo{
			Name:      name,
			Cluster:   c.Cluster,
			Namespace: c.Namespace,
			IsCurrent: name == cfg.CurrentContext,
		})
	}

	return &kubeProvider{
		raw:     clientcmd.NewDefaultClientConfig(*cfg, &clientcmd.ConfigOverrides{}),
		current: cfg.CurrentContext,
		infos:   infos,
		loader:  *rules,
		cache:   map[string]*ClientBundle{},
	}, nil
}

func (p *kubeProvider) Contexts() []ContextInfo { return p.infos }
func (p *kubeProvider) Current() string         { return p.current }

func (p *kubeProvider) Bundle(contextName string) (*ClientBundle, error) {
	if contextName == "" {
		contextName = p.current
	}
	p.mu.RLock()
	if b, ok := p.cache[contextName]; ok {
		p.mu.RUnlock()
		return b, nil
	}
	p.mu.RUnlock()

	b, err := p.build(contextName)
	if err != nil {
		return nil, err
	}
	p.mu.Lock()
	p.cache[contextName] = b
	p.mu.Unlock()
	return b, nil
}

func (p *kubeProvider) build(contextName string) (*ClientBundle, error) {
	restCfg, err := p.restConfig(contextName)
	if err != nil {
		return nil, err
	}
	typed, err := kubernetes.NewForConfig(restCfg)
	if err != nil {
		return nil, fmt.Errorf("typed client for %q: %w", contextName, err)
	}
	dyn, err := dynamic.NewForConfig(restCfg)
	if err != nil {
		return nil, fmt.Errorf("dynamic client for %q: %w", contextName, err)
	}
	disco := memory.NewMemCacheClient(typed.Discovery())
	mapper := restmapper.NewDeferredDiscoveryRESTMapper(disco)
	return &ClientBundle{Typed: typed, Dynamic: dyn, Discovery: disco, Mapper: mapper}, nil
}

func (p *kubeProvider) restConfig(contextName string) (*rest.Config, error) {
	// In-cluster sentinel keeps parity with the old single-cluster mode.
	if contextName == "in-cluster" {
		return rest.InClusterConfig()
	}
	overrides := &clientcmd.ConfigOverrides{CurrentContext: contextName}
	cc := clientcmd.NewNonInteractiveDeferredLoadingClientConfig(&p.loader, overrides)
	restCfg, err := cc.ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("rest config for %q: %w", contextName, err)
	}
	return restCfg, nil
}
