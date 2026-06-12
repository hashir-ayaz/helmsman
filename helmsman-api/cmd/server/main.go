// Package main is the entry point for the Helmsman API server.
//
//	@title			Helmsman API
//	@version		1.0
//	@description	Local Kubernetes cluster management API. Connects to whichever cluster your kubeconfig points at.
//	@host			localhost:8080
//	@BasePath		/
package main

import (
	"log"

	_ "github.com/hashir-ayaz/helmsman/helmsman-api/docs"

	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/cluster"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/config"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/handler"
	"github.com/hashir-ayaz/helmsman/helmsman-api/internal/server"
)

func main() {
	cfg := config.Load()

	provider, err := cluster.NewProvider(cfg.KubeconfigPath)
	if err != nil {
		log.Fatalf("cluster provider: %v", err)
	}

	srv := server.New(cfg.Port, handler.New(provider))
	if err := srv.Start(); err != nil {
		log.Fatalf("server: %v", err)
	}
}
