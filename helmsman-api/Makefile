SWAG := $(shell go env GOPATH)/bin/swag

.PHONY: run build tidy docs

run:
	go run ./cmd/server

build:
	go build -o bin/helmsman-api ./cmd/server

tidy:
	go mod tidy

docs:
	$(SWAG) init -g cmd/server/main.go --parseInternal -o docs
