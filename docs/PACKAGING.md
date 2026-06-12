# Packaging Helmsman into a DMG

Helmsman ships as a single macOS app. The SwiftUI frontend (`helmsman-frontend`)
embeds the compiled Go backend (`helmsman-api`) as a **sidecar**: the app launches
the backend as a child process on startup, talks to it over `http://127.0.0.1`,
and shuts it down on quit. The user double-clicks one `.app`; the backend is
invisible.

```
Helmsman.app/
  Contents/
    MacOS/
      k67s                  # SwiftUI app binary
    Resources/
      helmsman-api          # embedded universal Go binary (arm64 + x86_64)
```

This document describes the architecture, the one-time project setup, the
day-to-day dev workflow, and the release pipeline.

---

## 1. Why the App Sandbox is disabled

Helmsman is a developer/admin tool: the backend reads `~/.kube/config` and talks
to arbitrary cluster API servers, frequently through **exec credential plugins**
(`aws eks get-token`, `gke-gcloud-auth-plugin`, `kubelogin`, …) that spawn helper
binaries. None of that works inside the App Sandbox, which confines file access
to the app's container and blocks child-process credential helpers.

So the sandbox is **off** and we distribute outside the Mac App Store using
**Developer ID signing + notarization** (the same path k9s, Lens, and OpenLens
take). This is already configured:

- `helmsman-frontend/k67s/k67s.entitlements` — the `com.apple.security.app-sandbox`
  key has been removed (only `network.client` remains, which is harmless without
  the sandbox).
- `helmsman-frontend/k67s.xcodeproj` — `ENABLE_APP_SANDBOX = NO` in both the Debug
  and Release configurations. `ENABLE_HARDENED_RUNTIME = YES` stays on (required
  for notarization).

> Hardened Runtime + a Go sidecar needs **no special entitlements** — Go's static
> binaries run fine under it. The child just has to be signed (notarization
> checks every Mach-O in the bundle).

---

## 2. How the sidecar works

### Startup / shutdown (Swift)

`helmsman-frontend/k67s/Services/BackendProcess.swift` owns the lifecycle, wired
in via an `NSApplicationDelegate` in `k67sApp.swift`:

- `applicationDidFinishLaunching` → `BackendProcess.shared.start()`
- `applicationWillTerminate` → `BackendProcess.shared.stop()`

`start()`:
1. Looks for the bundled `helmsman-api` in `Contents/Resources`.
   - **Not found** (running from Xcode without embedding) → no-op; the app keeps
     the default `http://127.0.0.1:8080` and expects a backend started via
     `make run`. This is the normal dev mode.
   - **Found** (packaged build) → continues.
2. Picks a free localhost TCP port (binds `:0`, reads the assigned port).
3. Calls `KubeAPIClient.configure(port:)` so all requests target that port.
4. Spawns the backend with `PORT=<port>`, an inherited+widened `PATH`, and
   `HELMSMAN_PARENT_WATCH=1`, wiring the child's `stdin` to a pipe it holds open.

The free-port handshake means two copies of the app (or an unrelated service on
8080) never collide.

### `PATH` widening

GUI apps launched from Finder inherit a minimal `PATH` (`/usr/bin:/bin:…`), so
Homebrew/krew-installed exec plugins would be invisible to the backend.
`BackendProcess` prepends `/opt/homebrew/bin`, `/opt/homebrew/sbin`,
`/usr/local/bin`, `~/.krew/bin`, and `~/bin` to the child's `PATH`.

### Orphan prevention (Go)

`helmsman-api/cmd/server/main.go` adds `watchParentDeath()`: when
`HELMSMAN_PARENT_WATCH` is set it reads `stdin` in a goroutine. If the host app
crashes or is force-quit without calling `stop()`, the pipe closes, the read
returns EOF, and the backend signals itself `SIGTERM` to run its normal graceful
shutdown. No orphaned servers. It's a no-op for standalone `make run`.

### Configurable port (Swift)

`KubeAPIClient.baseURL` is now a `nonisolated(unsafe) static var` (was a hardcoded
`let`), written once at launch before any request via `KubeAPIClient.configure(port:)`.

---

## 3. Dev workflow (unchanged)

Running from Xcode does **not** embed the binary, so:

```bash
# terminal 1 — backend
cd helmsman-api && make run        # listens on :8080

# Xcode — run the k67s scheme; the app connects to :8080
```

---

## 4. One-time project setup

Already applied in this repo; listed here for reference / new clones.

| What | Where | Value |
|---|---|---|
| Disable sandbox | `k67s.entitlements` | remove `com.apple.security.app-sandbox` |
| Disable sandbox | `k67s.xcodeproj` build settings | `ENABLE_APP_SANDBOX = NO` (Debug + Release) |
| Hardened Runtime | `k67s.xcodeproj` build settings | `ENABLE_HARDENED_RUNTIME = YES` (already on) |
| Signing | Signing & Capabilities | Team `UUZ96V7V4P`, "Developer ID Application" for release |

New `.swift` files don't need to be added to the project manually — the target
uses a **synchronized folder group**, so anything under `helmsman-frontend/k67s/`
is included automatically.

---

## 5. Release pipeline

Everything is automated by `scripts/package.sh`. It does **not** rely on an Xcode
build phase — it builds an unsigned app, embeds the binary, then signs
inside-out, so it is fully reproducible from the terminal (and CI).

### Prerequisites

- Xcode command-line tools (`xcodebuild`, `codesign`, `xcrun`).
- Go toolchain (for `make build-universal`).
- Optional: [`create-dmg`](https://github.com/create-dmg/create-dmg)
  (`brew install create-dmg`). Falls back to `hdiutil` if absent.
- For notarization: a **Developer ID Application** certificate and a stored
  notarytool profile:

  ```bash
  xcrun notarytool store-credentials "helmsman-notary" \
    --apple-id "you@example.com" --team-id UUZ96V7V4P \
    --password "app-specific-password"   # https://appleid.apple.com
  ```

### Run it

```bash
# Signed + notarized release
DEVELOPER_ID_APP="Developer ID Application: Your Name (UUZ96V7V4P)" \
NOTARY_PROFILE="helmsman-notary" \
./scripts/package.sh

# Local test build (ad-hoc signed, no notarization)
./scripts/package.sh
```

Output: `build/dist/Helmsman.dmg`.

### What it does (6 steps)

1. **`make -C helmsman-api build-universal`** — `lipo`-merged arm64 + amd64
   binary at `helmsman-api/bin/helmsman-api`.
2. **`xcodebuild … CODE_SIGNING_ALLOWED=NO build`** — unsigned `k67s.app`.
3. **Embed** the universal binary into `Contents/Resources/helmsman-api`.
4. **Sign inside-out** — the embedded binary first, then the app (with
   `--options runtime --timestamp` and the entitlements file). Verifies with
   `codesign --verify --deep --strict`.
5. **Build the DMG** (`create-dmg`, else `hdiutil` with an `/Applications` drop
   link).
6. **Notarize + staple** the DMG (skipped unless both `DEVELOPER_ID_APP` and
   `NOTARY_PROFILE` are set).

### Configuration knobs (env vars)

| Var | Default | Meaning |
|---|---|---|
| `SCHEME` | `k67s` | Xcode scheme |
| `CONFIGURATION` | `Release` | Build configuration |
| `VOLNAME` | `Helmsman` | DMG/volume name |
| `DEVELOPER_ID_APP` | _(empty)_ | Signing identity; empty → ad-hoc (local only) |
| `NOTARY_PROFILE` | _(empty)_ | notarytool keychain profile; empty → skip notarization |

---

## 6. Optional: self-embedding Xcode build phase

If you'd rather have Xcode Release builds embed the binary directly (so an
Xcode "Archive" is already complete), add a **Run Script** build phase to the
`k67s` target *before* the existing phases:

```bash
set -e
make -C "$SRCROOT/../helmsman-api" build-universal
cp "$SRCROOT/../helmsman-api/bin/helmsman-api" \
   "${CODESIGNING_FOLDER_PATH}/Contents/Resources/helmsman-api"
codesign --force --options runtime --timestamp \
  --sign "${EXPANDED_CODE_SIGN_IDENTITY_NAME}" \
  "${CODESIGNING_FOLDER_PATH}/Contents/Resources/helmsman-api"
```

You must also set **`ENABLE_USER_SCRIPT_SANDBOXING = NO`** for that target —
otherwise the script phase can't run `go build` (network/module cache) or write
into the build product. The standalone `scripts/package.sh` avoids this entirely,
which is why it is the recommended path.

---

## 7. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| App opens but every request fails with a connection error | Backend didn't start. Check Console.app, subsystem `hashir-ayaz.k67s`, category `backend`. In dev, ensure `make run` is up. |
| Cluster auth fails only in the packaged app (works in terminal) | Exec credential plugin not on the GUI `PATH`. Confirm it lives in one of the widened paths in `BackendProcess.childEnvironment`, or add its directory there. |
| "Helmsman is damaged and can't be opened" on another Mac | DMG not notarized/stapled. Run the pipeline with `DEVELOPER_ID_APP` + `NOTARY_PROFILE`. |
| Notarization rejected: "The binary is not signed with a valid Developer ID" | The embedded `helmsman-api` wasn't signed, or Hardened Runtime is off. The script signs it; verify with `codesign -dvv Helmsman.app/Contents/Resources/helmsman-api`. |
| Leftover `helmsman-api` process after a crash | Should self-terminate via the parent-death watchdog. If you ran a build *without* `HELMSMAN_PARENT_WATCH`, kill it manually. |
| Port already in use | Not possible in packaged builds (free port chosen at launch). In dev, change `PORT` for `make run`. |
