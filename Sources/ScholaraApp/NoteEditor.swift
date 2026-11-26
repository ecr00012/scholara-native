import SwiftUI

/// The placeholder and insertion point share TextKit's own text origin and font.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.readingPalette) private var palette
    var placeholder = "Write a note about this passage…"
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NoteScrollView()
        scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let view = PlaceholderTextView(frame: .zero)
        view.isRichText = false; view.isEditable = true; view.isSelectable = true; view.allowsUndo = true
        view.drawsBackground = false; view.font = .systemFont(ofSize: 14)
        view.textContainerInset = NSSize(width: 12, height: 12); view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.delegate = context.coordinator; view.setAccessibilityLabel("Note text")
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? PlaceholderTextView else { return }
        context.coordinator.text = $text
        if view.string != text { view.string = text }
        view.placeholder = placeholder; view.placeholderColor = palette.inkNS.withAlphaComponent(0.55)
        view.textColor = palette.inkNS; view.insertionPointColor = palette.inkNS
        view.needsDisplay = true; scroll.needsLayout = true
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string; view.needsDisplay = true; view.enclosingScrollView?.needsLayout = true
        }
    }
}
final class PlaceholderTextView: NSTextView {
    var placeholder = ""
    var placeholderColor = NSColor.secondaryLabelColor
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 14), .foregroundColor: placeholderColor])
        }
    }
}

struct NoteInput: View {
    @Binding var text: String
    @Environment(\.readingPalette) private var palette
    var body: some View {
        NoteEditor(text: $text)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(palette.outline, lineWidth: 1) }
    }
}

final class NoteScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let text = documentView as? NSTextView, let container = text.textContainer, let manager = text.layoutManager, contentSize.width > 0 else { return }
        container.containerSize = NSSize(width: max(1, contentSize.width - 24), height: CGFloat.greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let size = NSSize(width: contentSize.width, height: max(contentSize.height, manager.usedRect(for: container).height + 24))
        if text.frame.size != size { text.setFrameSize(size) }
    }
}
