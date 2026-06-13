import SwiftUI

/// A label/value row with a fixed-width label column.
struct DetailRow: View {
    let label: String
    let value: String
    var valueColor: Color? = nil

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.callout)
                .foregroundStyle(valueColor ?? .primary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
