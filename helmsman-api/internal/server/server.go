package server

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	httpSwagger "github.com/swaggo/http-swagger"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/handler"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/k8s"
)

type Server struct {
	http *http.Server
}

func New(port string, h handler.Handlers) *Server {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", health)
	mux.HandleFunc("/swagger/", httpSwagger.WrapHandler)

	mux.HandleFunc("GET /api/v1/status", h.Status.Get)
	mux.HandleFunc("GET /api/v1/contexts", h.Contexts.List)

	// Generic resources.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/resources", h.Resources.Apply)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/resources/{resource}", h.Resources.List)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}", h.Resources.List)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/resources/{resource}/{name}", h.Resources.Get)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/resources/{resource}/{name}/yaml", h.Resources.YAML)
	mux.HandleFunc("DELETE /api/v1/contexts/{ctx}/resources/{resource}/{name}", h.Resources.Delete)
	mux.HandleFunc("PATCH /api/v1/contexts/{ctx}/resources/{resource}/{name}", h.Resources.Patch)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}", h.Resources.Get)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}/yaml", h.Resources.YAML)
	mux.HandleFunc("DELETE /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}", h.Resources.Delete)
	mux.HandleFunc("PATCH /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/{name}", h.Resources.Patch)

	// Actions.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/deployments/{name}/scale", h.Actions.Scale)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/scale", h.Actions.Scale)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/restart", h.Actions.Restart)

	// Suspend / Resume / CancelJob.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/suspend", h.Actions.Suspend)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/resume", h.Actions.Resume)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/jobs/{name}/cancel", h.Actions.CancelJob)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/cronjobs/{name}/trigger", h.Actions.TriggerCronJob)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/persistentvolumeclaims/{name}/resize", h.Actions.ResizePVC)

	// Node drain.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/nodes/{name}/drain", h.Actions.DrainNode)

	// Logs (SSE).
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/log", h.Logs.Stream)

	// Watch (SSE).
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/resources/{resource}/watch", h.Watch.Stream)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/resources/{resource}/watch", h.Watch.Stream)

	// Rollout operations.
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/history", h.Rollout.History)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/undo", h.Rollout.Undo)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/pause", h.Rollout.Pause)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/{workload}/{name}/rollout/resume", h.Rollout.Resume)

	// Port-forward sessions.
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/pods/{name}/portforward", h.PortForward.StartPod)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/namespaces/{ns}/services/{name}/portforward", h.PortForward.StartService)
	mux.HandleFunc("GET /api/v1/contexts/{ctx}/portforwards", h.PortForward.List)
	mux.HandleFunc("POST /api/v1/contexts/{ctx}/portforwards/{id}/stop", h.PortForward.Stop)
	mux.HandleFunc("DELETE /api/v1/contexts/{ctx}/portforwards/{id}", h.PortForward.Remove)

	return &Server{
		http: &http.Server{
			Addr:              fmt.Sprintf(":%s", port),
			Handler:           handler.Recoverer(mux),
			ReadHeaderTimeout: 15 * time.Second,
			// No global WriteTimeout: log streaming is long-lived (§10 decision 1).
		},
	}
}

func (s *Server) Start() error {
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)

	go func() {
		log.Printf("listening on %s", s.http.Addr)
		if err := s.http.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			log.Fatalf("server error: %v", err)
		}
	}()

	<-quit
	log.Println("shutting down...")
	k8s.DefaultPortForwardManager().StopAll()

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	return s.http.Shutdown(ctx)
}

func health(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}
