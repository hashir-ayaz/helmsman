package handler

import (
	"encoding/json"
	"net/http"
)

// APIResponse is the standard envelope returned by every endpoint.
type APIResponse struct {
	Data  any    `json:"data"`
	Error string `json:"error,omitempty"`
	Code  string `json:"code,omitempty"`
}

func writeSuccess(w http.ResponseWriter, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	json.NewEncoder(w).Encode(APIResponse{Data: data})
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeErrorCode(w, status, "", msg)
}

func writeErrorCode(w http.ResponseWriter, status int, code, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(APIResponse{Error: msg, Code: code})
}

// writeMappedError maps a Kubernetes / connectivity error to HTTP status + typed code.
func writeMappedError(w http.ResponseWriter, err error) {
	status, code, msg := statusFromK8sErr(err)
	writeErrorCode(w, status, code, msg)
}

// writeStatus writes a success payload with a non-200 status (e.g. 201 Created).
func writeStatus(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(APIResponse{Data: data})
}
