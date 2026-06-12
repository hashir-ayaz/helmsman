import SwiftUI

/// A monospaced text editor with a right-aligned line-number gutter. Native — no
/// syntax highlighting, no third-party dependencies.
struct CodeEditorView: View {
    @Binding var text: String

    private var lineCount: Int {
        max(1, text.reduce(into: 1) { count, ch in if ch == "\n" { count += 1 } })
    }

    var body: some View {
        ScrollView([.vertical]) {
            HStack(alignment: .top, spacing: 0) {
                gutter
                Divider()
                TextEditor(text: $text)
                    .font(font)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .frame(minHeight: 400, alignment: .topLeading)
                    .padding(.leading, 6)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var gutter: some View {
        VStack(alignment: .trailing, spacing: 0) {
            ForEach(1...lineCount, id: \.self) { line in
                Text("\(line)")
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: 36, alignment: .trailing)
            }
        }
        .padding(.top, 8)        // Align with TextEditor's default top inset.
        .padding(.trailing, 6)
        .padding(.leading, 8)
    }

    private var font: Font {
        .system(.caption, design: .monospaced)
    }
}
