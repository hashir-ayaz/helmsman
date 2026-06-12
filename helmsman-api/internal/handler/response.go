package handler

import (
	"encoding/json"
	"net/http"
)

// APIResponse is the standard envelope returned by every endpoint.
type APIResponse struct {
	Data  any    `json:"data"`
	Error string `json:"error,omitempty"`
}

func writeSuccess(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(APIResponse{Data: data})
}

func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(APIResponse{Error: msg})
}

// writeStatus writes a success payload with a non-200 status (e.g. 201 Created).
func writeStatus(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(APIResponse{Data: data})
}
