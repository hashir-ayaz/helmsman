<!-- Generated: 2026-07-11 -->

# Event Overview Detail Panel — Design

## Goal

When a user selects an Event in the Events list, the right-hand detail Overview tab should show Lens-style event metadata and the **full message** in a clear bordered well — not only generic kind/name/namespace/age/UID.

## Scope

**In scope**
- Events resource detail Overview tab only (`kind == "Event"`)
- Metadata rows + Message section matching the reference layout
- Optional header StatusDot derived from event `type` (Warning → failed color)

**Out of scope**
- Pod overview embedded event rows
- Cluster Overview warning rows
- Events list Message column multi-line / tooltip
- Backend or API changes

## Current behavior

Selecting an Event falls through to `GenericOverview` via `ResourceOverview`’s `default` branch. The Event object’s `message`, `reason`, `type`, `count`, `involvedObject`, `source`, and timestamps are never rendered on Overview.

## Design

### Routing

Add `case "Event": EventOverview(object: object)` in `ResourceOverview.kindOverview` before `default`.

### New view: `EventOverview.swift`

Two sections, then existing `CommonMetadataSection` (labels/annotations) continues to append via `ResourceOverview` as today.

#### Section: Overview

| Label | Source |
|-------|--------|
| Type | `object["type"]` — color: Warning → failed/orange-red, Normal → secondary/primary |
| Reason | `object["reason"]` — `ResourceColors.eventReasonColor(reason)` |
| Kind | `object["involvedObject"]?["kind"]` |
| Name | `object["involvedObject"]?["name"]` |
| Namespace | `object["involvedObject"]?["namespace"]` (omit if empty) |
| Count | `object["count"]` (display string / int) |
| Source | `source.component`, optionally append `source.host` if present |
| First Seen | best available: `firstTimestamp` → else `eventTime` → else `metadata.creationTimestamp` |
| Last Seen | best available: `lastTimestamp` → else `series.lastObservedTime` → else `eventTime` → else First Seen |

Use existing `DetailSection` + `DetailRow`. Omit rows whose values are missing/empty.

Timestamps: format for human readability (e.g. `11-Jul-2026 at 8:50:04 PM`) via a small helper on `K8s` (or local to the view). Fall back to raw string if parse fails.

#### Section: Message

- Title: `Message` via `DetailSection`
- Body: full `object["message"]` string
- Styling: padded text in a rounded rectangle well (secondary/fill background + subtle stroke), matching Helmsman detail density — inspired by `ContainerCard.reasonCallout` but neutral (not orange) since messages are informational
- Full wrap (`fixedSize(horizontal: false, vertical: true)`), `.textSelection(.enabled)`
- If message missing/empty: omit the Message section entirely

### Header polish (`ResourceDetailView`)

When `object["kind"] == "Event"` and `type` is present:
- Show `StatusDot` using a status string mapped from type (`Warning` → `"Failed"` / warning color path already used elsewhere; `Normal` → `"Running"` or a calm status)

No other header changes.

### Files

| Action | Path |
|--------|------|
| Create | `helmsman-frontend/k67s/Views/Detail/Overviews/EventOverview.swift` |
| Edit | `helmsman-frontend/k67s/Views/Detail/ResourceOverview.swift` — add `Event` case |
| Edit (optional small) | `helmsman-frontend/k67s/Views/Detail/K8sObjectHelpers.swift` — timestamp formatter + optional source/involved helpers |
| Edit (optional small) | `helmsman-frontend/k67s/Views/ResourceDetailView.swift` — Event type StatusDot |

Xcode uses `PBXFileSystemSynchronizedRootGroup` — new Swift files under `k67s/` are picked up automatically; no `pbxproj` edit.

### Testing

Manual (no Swift test target yet):
1. Open Events list, select an Event with a long message → Message well shows full untruncated text
2. Confirm Type, Reason, Kind, Name, Namespace, Count, Source, First/Last Seen match the object
3. Warning vs Normal Type coloring; critical Reason coloring
4. Event with missing optional fields still renders without empty rows
5. Non-Event resources unchanged

## Success criteria

- Events Overview matches the reference’s information hierarchy: metadata list + clear Message well
- Message is never truncated in the detail panel
- No regressions for other resource kinds
