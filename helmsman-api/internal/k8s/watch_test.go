package k8s

import (
	"context"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	watchpkg "k8s.io/apimachinery/pkg/watch"
	dynamicfake "k8s.io/client-go/dynamic/fake"
	k8stesting "k8s.io/client-go/testing"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
)

func newFakePod(name, ns, rv string) *unstructured.Unstructured {
	return &unstructured.Unstructured{Object: map[string]any{
		"apiVersion": "v1", "kind": "Pod",
		"metadata": map[string]any{"name": name, "namespace": ns, "resourceVersion": rv},
	}}
}

func fakeWatchSetup() (*dynamicfake.FakeDynamicClient, *watchpkg.FakeWatcher) {
	dynClient := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())
	fw := watchpkg.NewFake()
	dynClient.PrependWatchReactor("*", func(_ k8stesting.Action) (bool, watchpkg.Interface, error) {
		return true, fw, nil
	})
	return dynClient, fw
}

func podRef() ResourceRef {
	return ResourceRef{
		GVR:        schema.GroupVersionResource{Version: "v1", Resource: "pods"},
		Namespaced: true,
	}
}

func TestWatch_deliversModifiedEvent(t *testing.T) {
	dynClient, fw := fakeWatchSetup()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	b := &cluster.ClientBundle{Dynamic: dynClient}
	ch, err := Watch(ctx, b, podRef(), "default", ListOptions{})
	if err != nil {
		t.Fatal(err)
	}

	go func() {
		time.Sleep(10 * time.Millisecond)
		fw.Modify(newFakePod("my-pod", "default", "100"))
	}()

	select {
	case event := <-ch:
		if event.Type != "MODIFIED" {
			t.Errorf("want MODIFIED, got %s", event.Type)
		}
		if event.Name != "my-pod" {
			t.Errorf("want my-pod, got %s", event.Name)
		}
		if event.Namespace != "default" {
			t.Errorf("want default, got %s", event.Namespace)
		}
	case <-ctx.Done():
		t.Fatal("timed out waiting for event")
	}
}

func TestWatch_closesChannelOnContextCancel(t *testing.T) {
	dynClient, _ := fakeWatchSetup()
	ctx, cancel := context.WithCancel(context.Background())
	b := &cluster.ClientBundle{Dynamic: dynClient}

	ch, err := Watch(ctx, b, podRef(), "default", ListOptions{})
	if err != nil {
		t.Fatal(err)
	}

	cancel()

	select {
	case _, open := <-ch:
		if open {
			t.Error("channel should be closed after context cancel")
		}
	case <-time.After(3 * time.Second):
		t.Fatal("channel not closed within 3 seconds of cancel")
	}
}

func TestWatch_deliversAddedAndDeletedEvents(t *testing.T) {
	dynClient, fw := fakeWatchSetup()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	b := &cluster.ClientBundle{Dynamic: dynClient}
	ch, err := Watch(ctx, b, podRef(), "default", ListOptions{})
	if err != nil {
		t.Fatal(err)
	}

	go func() {
		time.Sleep(10 * time.Millisecond)
		fw.Add(newFakePod("new-pod", "default", "200"))
		time.Sleep(10 * time.Millisecond)
		fw.Delete(newFakePod("new-pod", "default", "201"))
	}()

	var types []string
	for i := 0; i < 2; i++ {
		select {
		case e := <-ch:
			types = append(types, e.Type)
		case <-ctx.Done():
			t.Fatalf("timed out after receiving %v", types)
		}
	}
	if types[0] != "ADDED" || types[1] != "DELETED" {
		t.Errorf("want [ADDED DELETED], got %v", types)
	}
}

func TestWatch_passesLabelSelector(t *testing.T) {
	dynClient := dynamicfake.NewSimpleDynamicClient(runtime.NewScheme())
	var gotSelector string
	dynClient.PrependWatchReactor("*", func(action k8stesting.Action) (bool, watchpkg.Interface, error) {
		if watch, ok := action.(k8stesting.WatchAction); ok {
			gotSelector = watch.GetWatchRestrictions().Labels.String()
		}
		return true, watchpkg.NewFake(), nil
	})

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	b := &cluster.ClientBundle{Dynamic: dynClient}
	ch, err := Watch(ctx, b, podRef(), "default", ListOptions{LabelSelector: "app=nginx"})
	if err != nil {
		t.Fatal(err)
	}
	cancel()
	<-ch

	if gotSelector != "app=nginx" {
		t.Errorf("want label selector app=nginx, got %q", gotSelector)
	}
}
