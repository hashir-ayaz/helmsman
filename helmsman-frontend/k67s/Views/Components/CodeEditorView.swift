import AppKit
import Highlightr
import SwiftUI

/// A monospaced YAML editor with syntax highlighting and a line-number gutter.
struct CodeEditorView: View {
    @Binding var text: String
    @Environment(\.colorScheme) private var colorScheme

    private var lineCount: Int {
        max(1, text.reduce(into: 1) { count, ch in if ch == "\n" { count += 1 } })
    }

    var body: some View {
        ScrollView([.vertical]) {
            HStack(alignment: .top, spacing: 0) {
                gutter
                Divider()
                HighlightingTextView(text: $text, colorScheme: colorScheme)
                    .frame(minHeight: 400, alignment: .topLeading)
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
        .padding(.top, 8)
        .padding(.trailing, 6)
        .padding(.leading, 8)
    }

    private var font: Font {
        .system(.caption, design: .monospaced)
    }
}

// MARK: - Highlighting NSTextView

private struct HighlightingTextView: NSViewRepresentable {
    @Binding var text: String
    let colorScheme: ColorScheme

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, colorScheme: colorScheme)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isRichText = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.backgroundColor = .textBackgroundColor
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.applyHighlight(to: textView, text: text, colorScheme: colorScheme)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parentText = $text

        if context.coordinator.isUpdating { return }

        if textView.string != text {
            context.coordinator.isUpdating = true
            context.coordinator.applyHighlight(to: textView, text: text, colorScheme: colorScheme)
            context.coordinator.isUpdating = false
        } else if context.coordinator.colorScheme != colorScheme {
            context.coordinator.colorScheme = colorScheme
            context.coordinator.applyHighlight(to: textView, text: textView.string, colorScheme: colorScheme)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parentText: Binding<String>
        var colorScheme: ColorScheme
        weak var textView: NSTextView?
        var isUpdating = false
        private let highlightr: Highlightr?

        init(text: Binding<String>, colorScheme: ColorScheme) {
            self.parentText = text
            self.colorScheme = colorScheme
            self.highlightr = Highlightr()
            super.init()
        }

        func applyHighlight(to textView: NSTextView, text: String, colorScheme: ColorScheme) {
            guard let highlightr else {
                textView.string = text
                return
            }

            let theme = colorScheme == .dark ? "atom-one-dark" : "atom-one-light"
            highlightr.setTheme(to: theme)
            let selected = textView.selectedRanges
            let highlighted = highlightr.highlight(text, as: "yaml")
                ?? NSAttributedString(
                    string: text,
                    attributes: [.font: NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)]
                )
            textView.textStorage?.setAttributedString(highlighted)
            if !selected.isEmpty {
                textView.selectedRanges = selected
            }
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView else { return }
            parentText.wrappedValue = textView.string
            isUpdating = true
            applyHighlight(to: textView, text: textView.string, colorScheme: colorScheme)
            isUpdating = false
        }
    }
}
