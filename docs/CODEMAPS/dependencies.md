<!-- Generated: 2026-07-10 | Files scanned: 97 | Token estimate: ~550 -->

# Dependencies

## External Services

| Service | Consumer | Purpose |
|---------|----------|---------|
| Kubernetes API | helmsman-api | Primary data source (all CRUD/actions) |
| kubeconfig exec plugins | helmsman-api | Cloud auth (`aws`, `gcloud`, `kubelogin`, etc.) |
| Supabase Storage | helmsman-landing | DMG download hosting |
| GitHub | helmsman-landing | `git clone` source link |
| Homebrew | helmsman-landing | Cask distribution (`hashir-ayaz/helmsman`) |
| kubectl (local) | helmsman-frontend | Shell feature (`kubectl exec`) |

## helmsman-api (Go)

| Dependency | Version | Role |
|------------|---------|------|
| `k8s.io/client-go` | v0.32.3 | dynamic + typed K8s clients |
| `k8s.io/api`, `k8s.io/apimachinery` | v0.32.3 | K8s types, Table, meta |
| `sigs.k8s.io/yaml` | v1.4.0 | YAML marshal/unmarshal |
| `github.com/swaggo/swag` | v1.16.6 | OpenAPI doc generation |
| `github.com/swaggo/http-swagger` | v1.3.4 | `/swagger/` UI |

Indirect: oauth2, protobuf, json-patch, restful — pulled by client-go.

## helmsman-frontend (Swift)

| Dependency | Role |
|------------|------|
| SwiftUI / AppKit | UI framework |
| Foundation / OSLog | HTTP, logging |
| URLSession | REST + SSE streaming |
| Darwin | PTY for shell terminal |

No Swift Package Manager deps in tree — stdlib + Apple frameworks only.

## helmsman-landing (npm)

| Package | Version | Role |
|---------|---------|------|
| `next` | 16.2.9 | App framework |
| `react`, `react-dom` | 19.2.4 | UI |
| `tailwindcss` | ^4 | Styling |
| `radix-ui` | ^1.5.0 | Primitives |
| `lucide-react` | ^1.17.0 | Icons |
| `clsx`, `tailwind-merge`, `class-variance-authority` | — | className utilities |
| `shadcn` | ^4.11.0 | Component tooling |

## Monorepo Shared Conventions

- `CLAUDE.md` — canonical architecture reference at repo root
- `build/assets/` — shared icon/DMG assets (not a runtime package)
- No shared code library between Go/Swift/Next — HTTP API is the integration boundary

## Dev Tooling

| Tool | Package | Command |
|------|---------|---------|
| Go | helmsman-api | `make run`, `make build`, `make docs`, `make tidy` |
| Xcode | helmsman-frontend | Open `k67s.xcodeproj` |
| Node | helmsman-landing | `npm run dev` |
| swag | helmsman-api | `make docs` (regenerates `docs/docs.go`) |
