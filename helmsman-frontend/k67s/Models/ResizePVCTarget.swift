import Foundation

/// Context for the PVC resize sheet, parsed from a table row.
struct ResizePVCTarget: Identifiable {
    let row: TablePayload.Row
    let currentRequest: String
    let capacity: String
    let storageClass: String
    let initialValue: String
    let initialUnit: String

    var id: String { row.id }

    var namespaceName: String {
        let ns = row.object.namespace ?? ""
        return ns.isEmpty ? row.object.name : "\(ns)/\(row.object.name)"
    }

    /// Splits a Kubernetes quantity like `42Gi` into value + unit.
    static func parseQuantity(_ quantity: String) -> (value: String, unit: String) {
        let trimmed = quantity.trimmingCharacters(in: .whitespacesAndNewlines)
        for unit in ["Ti", "Gi", "Mi", "Ki"] {
            if trimmed.hasSuffix(unit) {
                let value = String(trimmed.dropLast(unit.count))
                return (value, unit)
            }
        }
        return (trimmed, "Gi")
    }
}

enum PVCResizeUnit: String, CaseIterable, Identifiable {
    case mi = "Mi"
    case gi = "Gi"
    case ti = "Ti"

    var id: String { rawValue }
}
