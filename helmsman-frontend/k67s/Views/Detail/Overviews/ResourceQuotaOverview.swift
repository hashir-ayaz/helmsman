import SwiftUI

struct ResourceQuotaOverview: View {
    let object: JSONValue

    var body: some View {
        DetailSection(title: "Overview") {
            VStack(alignment: .leading, spacing: 4) {
                if let name = object["metadata"]?["name"]?.stringValue {
                    DetailRow(label: "Name", value: name)
                }
                if let ns = object["metadata"]?["namespace"]?.stringValue {
                    DetailRow(label: "Namespace", value: ns)
                }
                if let age = K8s.age(from: object["metadata"]?["creationTimestamp"]?.stringValue) {
                    DetailRow(label: "Age", value: age)
                }
                if let scopes = scopeSummary {
                    DetailRow(label: "Scopes", value: scopes)
                }
            }
        }

        if !quotaRows.isEmpty {
            DetailSection(title: "Quota") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(quotaRows, id: \.key) { row in
                        DetailRow(label: row.key, value: row.value, valueColor: row.color)
                    }
                }
            }
        }
    }

    private var scopeSummary: String? {
        guard let scopes = object["spec"]?["scopes"]?.arrayValue, !scopes.isEmpty else {
            return nil
        }
        let names = scopes.compactMap { $0.stringValue }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    private var quotaRows: [QuotaRow] {
        let hard = object["status"]?["hard"]?.objectValue
            ?? object["spec"]?["hard"]?.objectValue
            ?? [:]
        let used = object["status"]?["used"]?.objectValue ?? [:]
        guard !hard.isEmpty else { return [] }

        return hard.keys.sorted().map { key in
            let limit = hard[key]?.displayString ?? "—"
            let consumed = used[key]?.displayString ?? "0"
            let atOrOverLimit = isAtOrOverLimit(used: consumed, hard: limit)
            return QuotaRow(
                key: key,
                value: "\(consumed) / \(limit)",
                color: atOrOverLimit ? .orange : nil
            )
        }
    }

    private func isAtOrOverLimit(used: String, hard: String) -> Bool {
        guard let usedNum = parseQuantity(used), let hardNum = parseQuantity(hard), hardNum > 0 else {
            return false
        }
        return usedNum >= hardNum
    }

    /// Best-effort numeric compare for quota strings (ints, decimals, milli suffix).
    private func parseQuantity(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("m") {
            let num = trimmed.dropLast()
            return Double(num)
        }
        return Double(trimmed)
    }

    private struct QuotaRow {
        let key: String
        let value: String
        let color: Color?
    }
}
