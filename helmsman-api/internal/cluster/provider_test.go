package cluster

import (
	"os"
	"path/filepath"
	"testing"
)

const twoContextKubeconfig = `
apiVersion: v1
kind: Config
current-context: dev
clusters:
- name: dev-cluster
  cluster: {server: https://dev.example:6443}
- name: prod-cluster
  cluster: {server: https://prod.example:6443}
contexts:
- name: dev
  context: {cluster: dev-cluster, namespace: dev-ns}
- name: prod
  context: {cluster: prod-cluster}
users: []
`

func writeKubeconfig(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	if err := os.WriteFile(path, []byte(twoContextKubeconfig), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestProviderContexts(t *testing.T) {
	p, err := NewProvider(writeKubeconfig(t))
	if err != nil {
		t.Fatalf("NewProvider: %v", err)
	}
	if got := p.Current(); got != "dev" {
		t.Errorf("Current() = %q, want dev", got)
	}
	ctxs := p.Contexts()
	if len(ctxs) != 2 {
		t.Fatalf("got %d contexts, want 2", len(ctxs))
	}
	byName := map[string]ContextInfo{}
	for _, c := range ctxs {
		byName[c.Name] = c
	}
	if !byName["dev"].IsCurrent {
		t.Error("dev should be current")
	}
	if byName["dev"].Namespace != "dev-ns" {
		t.Errorf("dev namespace = %q, want dev-ns", byName["dev"].Namespace)
	}
	if byName["dev"].Cluster != "dev-cluster" {
		t.Errorf("dev cluster = %q, want dev-cluster", byName["dev"].Cluster)
	}
}
