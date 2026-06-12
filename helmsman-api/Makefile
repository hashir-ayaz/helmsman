SWAG := $(shell go env GOPATH)/bin/swag

.PHONY: run build build-universal tidy docs

run:
	go run ./cmd/server

build:
	go build -o bin/helmsman-api ./cmd/server

# Universal (arm64 + amd64) binary for embedding in the macOS .app bundle.
# CGO is off so these are fully static, cross-compilable binaries.
build-universal:
	CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -ldflags "-s -w" -o bin/helmsman-api-arm64 ./cmd/server
	CGO_ENABLED=0 GOOS=darwin GOARCH=amd64 go build -trimpath -ldflags "-s -w" -o bin/helmsman-api-amd64 ./cmd/server
	lipo -create -output bin/helmsman-api bin/helmsman-api-arm64 bin/helmsman-api-amd64
	rm -f bin/helmsman-api-arm64 bin/helmsman-api-amd64
	@echo "built universal bin/helmsman-api"

tidy:
	go mod tidy

docs:
	$(SWAG) init -g cmd/server/main.go --parseInternal -o docs
