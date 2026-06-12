package k8s

import (
	"testing"

	"k8s.io/apimachinery/pkg/api/meta/testrestmapper"
	"k8s.io/client-go/kubernetes/scheme"
)

func TestResolve(t *testing.T) {
	mapper := testrestmapper.TestOnlyStaticRESTMapper(scheme.Scheme)

	tests := []struct {
		param      string
		wantRes    string
		wantGroup  string
		namespaced bool
	}{
		{"pods", "pods", "", true},
		{"deployments", "deployments", "apps", true},
		{"deployments.apps", "deployments", "apps", true},
		{"namespaces", "namespaces", "", false},
		{"nodes", "nodes", "", false},
	}
	for _, tt := range tests {
		ref, err := Resolve(mapper, tt.param)
		if err != nil {
			t.Fatalf("Resolve(%q): %v", tt.param, err)
		}
		if ref.GVR.Resource != tt.wantRes || ref.GVR.Group != tt.wantGroup {
			t.Errorf("Resolve(%q) = %s/%s, want %s/%s", tt.param, ref.GVR.Group, ref.GVR.Resource, tt.wantGroup, tt.wantRes)
		}
		if ref.Namespaced != tt.namespaced {
			t.Errorf("Resolve(%q).Namespaced = %v, want %v", tt.param, ref.Namespaced, tt.namespaced)
		}
	}

	if _, err := Resolve(mapper, "widgets"); err == nil {
		t.Error("expected error for unknown resource")
	}
}
