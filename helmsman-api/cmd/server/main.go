// Package main is the entry point for the Helmsman API server.
//
//	@title			Helmsman API
//	@version		1.0
//	@description	Local Kubernetes cluster management API. Connects to whichever cluster your kubeconfig points at.
//	@host			localhost:8080
//	@BasePath		/
package main

import (
	"io"
	"log"
	"os"
	"syscall"

	_ "github.com/hashir-ayaz/helmsman/helmsman-api/docs"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/config"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/handler"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/server"
)

func main() {
	cfg := config.Load()

	watchParentDeath()

	provider := cluster.NewProvider(cfg.KubeconfigPath)
	if st := provider.Status(); !st.Ready {
		log.Printf("cluster not ready (%s): %s", st.Code, st.Message)
	}

	srv := server.New(cfg.Port, handler.New(provider))
	if err := srv.Start(); err != nil {
		log.Fatalf("server: %v", err)
	}
}

// watchParentDeath shuts the server down when its parent process goes away.
// When Helmsman launches this binary as an embedded sidecar it connects our
// stdin to a pipe it holds open and sets HELMSMAN_PARENT_WATCH. If the host app
// quits or crashes without terminating us, that pipe closes and the read below
// returns EOF — we then signal ourselves so the normal graceful shutdown runs.
// This prevents orphaned servers when run as a bundled sidecar; it is a no-op
// for plain `make run` / standalone use.
func watchParentDeath() {
	if os.Getenv("HELMSMAN_PARENT_WATCH") == "" {
		return
	}
	go func() {
		_, _ = io.Copy(io.Discard, os.Stdin)
		log.Println("parent process exited; shutting down")
		if p, err := os.FindProcess(os.Getpid()); err == nil {
			_ = p.Signal(syscall.SIGTERM)
		}
	}()
}
