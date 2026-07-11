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
	p := NewProvider(writeKubeconfig(t))
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
	st := p.Status()
	if !st.Ready || st.Code != "ready" {
		t.Errorf("Status() = %+v, want ready", st)
	}
}

func TestProviderMissingKubeconfig(t *testing.T) {
	path := filepath.Join(t.TempDir(), "missing-config")
	p := NewProvider(path)
	st := p.Status()
	if st.Ready {
		t.Fatal("expected not ready")
	}
	if st.Code != "kubeconfig_not_found" {
		t.Errorf("Code = %q, want kubeconfig_not_found", st.Code)
	}
	if st.Message == "" {
		t.Error("expected user-facing message")
	}
	if len(p.Contexts()) != 0 {
		t.Error("expected no contexts")
	}
	_, err := p.Bundle("")
	if err == nil {
		t.Fatal("expected Bundle error")
	}
	var nre *NotReadyError
	if !errorsAsNotReady(err, &nre) {
		t.Fatalf("Bundle error = %T %v, want *NotReadyError", err, err)
	}
}

func TestProviderNoContexts(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config")
	content := `
apiVersion: v1
kind: Config
clusters: []
contexts: []
users: []
`
	if err := os.WriteFile(path, []byte(content), 0o600); err != nil {
		t.Fatal(err)
	}
	p := NewProvider(path)
	st := p.Status()
	if st.Ready {
		t.Fatal("expected not ready")
	}
	if st.Code != "no_contexts" {
		t.Errorf("Code = %q, want no_contexts", st.Code)
	}
}

func errorsAsNotReady(err error, target **NotReadyError) bool {
	nre, ok := err.(*NotReadyError)
	if !ok {
		return false
	}
	*target = nre
	return true
}
