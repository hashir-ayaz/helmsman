import SwiftUI

/// Recursive collapsible tree for an arbitrary `JSONValue`. Objects and arrays
/// are expandable; scalars render as `key: value`.
struct JSONTreeView: View {
    let key: String?
    let value: JSONValue

    var body: some View {
        switch value {
        case .object(let dict):
            DisclosureGroup {
                ForEach(dict.keys.sorted(), id: \.self) { childKey in
                    JSONTreeView(key: childKey, value: dict[childKey] ?? .null)
                        .padding(.leading, 10)
                }
            } label: {
                branchLabel(suffix: "{\(dict.count)}")
            }
        case .array(let items):
            DisclosureGroup {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    JSONTreeView(key: "[\(index)]", value: item)
                        .padding(.leading, 10)
                }
            } label: {
                branchLabel(suffix: "[\(items.count)]")
            }
        default:
            HStack(alignment: .top, spacing: 4) {
                if let key {
                    Text("\(key):").foregroundStyle(.secondary)
                }
                Text(value.displayString)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func branchLabel(suffix: String) -> some View {
        HStack(spacing: 4) {
            Text(key ?? "root").fontWeight(.medium)
            Text(suffix).foregroundStyle(.tertiary)
        }
        .font(.system(.caption, design: .monospaced))
    }
}
