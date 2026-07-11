# Event Overview Detail Panel — Implementation Plan

> **For agentic workers:** Implement task-by-task in `.worktrees/event-overview-detail` on `feat/event-overview-detail`.

**Goal:** Lens-style Events detail Overview with metadata rows + full Message well.

**Architecture:** New `EventOverview` routed from `ResourceOverview`; helpers on `K8s` for timestamps/source; optional Event `StatusDot` in header.

**Tech Stack:** SwiftUI macOS, existing `DetailSection` / `DetailRow` / `JSONValue` / `ResourceColors`.

## Global Constraints

- Scope: Events resource detail only
- No pbxproj edit (synchronized root group)
- Match existing overview patterns; omit empty rows
- Neutral Message well (not orange)

---

### Task 1: K8s helpers

**Files:** `helmsman-frontend/k67s/Views/Detail/K8sObjectHelpers.swift`

- Add `displayTimestamp(_:)` → human format `dd-MMM-yyyy 'at' h:mm:ss a` (locale-aware), fallback to raw
- Add `eventSourceLabel(_:)` → `component` + optional `host`
- Add `eventFirstSeen` / `eventLastSeen` string pickers per spec fallbacks

### Task 2: EventOverview view

**Files:** create `helmsman-frontend/k67s/Views/Detail/Overviews/EventOverview.swift`

- Overview section with Type/Reason/Kind/Name/Namespace/Count/Source/First Seen/Last Seen
- Message section with bordered well, full wrap, text selection

### Task 3: Wire routing + header

**Files:**
- `ResourceOverview.swift` — `case "Event": EventOverview(object: object)`
- `ResourceDetailView.swift` — StatusDot from Event `type` (Warning→Failed, Normal→Running)

### Task 4: Commit + PR

- Commit, push branch, `gh pr create` into main
