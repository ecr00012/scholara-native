import SwiftUI
import ScholaraCore

struct NoteContent: View {
    @Environment(\.readingPalette) private var palette
    let note: Note
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: note.text.isEmpty ? "highlighter" : "note.text").font(.callout).foregroundStyle(palette.accent)
                Text(note.text.isEmpty ? "Highlight" : "Note").font(.custom("Iowan Old Style", size: 23)).foregroundStyle(palette.ink)
            }
            Rectangle().fill(palette.outline).frame(height: 1)
            if !note.quote.isEmpty {
                Text(note.quote).font(.system(size: 15, design: .serif)).lineSpacing(5)
                    .foregroundStyle(palette.muted).padding(.leading, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(palette.accent.opacity(0.65)).frame(width: 3) }
            }
            if !note.text.isEmpty { Text(note.text).font(.system(size: 14)).lineSpacing(4).foregroundStyle(palette.ink) }
        }.textSelection(.enabled)
    }
}
private struct StudyCard: ViewModifier {
    @Environment(\.readingPalette) private var palette
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(palette.outline, lineWidth: 1) }
    }
}
extension View { func studyCard() -> some View { modifier(StudyCard()) } }
