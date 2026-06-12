package config

import (
	"os"
	"path/filepath"
)

type Config struct {
	Port           string
	KubeconfigPath string
}

func Load() *Config {
	kubeconfigPath := os.Getenv("KUBECONFIG")
	if kubeconfigPath == "" {
		home, _ := os.UserHomeDir()
		kubeconfigPath = filepath.Join(home, ".kube", "config")
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	return &Config{
		Port:           port,
		KubeconfigPath: kubeconfigPath,
	}
}
