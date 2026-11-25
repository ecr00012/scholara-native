import SwiftUI
import ScholaraCore

struct DefinitionContent: View {
    @Environment(\.readingPalette) private var palette
    let entry: DictionaryEntry
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 16) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(entry.word).font(.custom("Iowan Old Style", size: compact ? 21 : 30)).foregroundStyle(palette.ink)
                if !entry.pronunciation.isEmpty { Text(entry.pronunciation).font(.system(size: compact ? 13 : 15)).foregroundStyle(palette.pronunciation).textSelection(.enabled) }
            }
            Rectangle().fill(palette.outline).frame(height: 1)
            ForEach(Array(entry.senses.enumerated()), id: \.offset) { _, sense in
                (Text(sense.partOfSpeech.isEmpty ? "" : sense.partOfSpeech + " · ").font(.custom("Iowan Old Style", size: compact ? 16 : 19).italic()).foregroundColor(palette.accent)
                 + Text(sense.gloss).font(.system(size: compact ? 14 : 17)).foregroundColor(palette.muted))
                    .lineSpacing(compact ? 5 : 8).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if !entry.origin.isEmpty {
                VStack(alignment: .leading, spacing: 5) { Text("ORIGIN").font(.caption.weight(.semibold)).tracking(1).foregroundStyle(palette.origin); Text(entry.origin).font(.system(size: compact ? 13 : 15)).foregroundStyle(palette.origin).lineSpacing(5).textSelection(.enabled) }.padding(.top, 6)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct DefinitionCard: View {
    @Environment(\.readingPalette) private var palette
    @ObservedObject var state: ReaderState
    @State private var editing = false
    var entry: DictionaryEntry { DictionaryEntry.parse(state.definition, word: state.word) }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Spacer(); Button { state.showDefinition = false } label: { Image(systemName: "xmark").font(.caption.weight(.semibold)) }.buttonStyle(.plain).foregroundStyle(palette.muted).accessibilityLabel("Close definition") }
            ScrollView { DefinitionContent(entry: entry).padding(.trailing, 5) }.frame(maxHeight: 380)
            HStack {
                if state.definitionSaved { Label("Saved to Vocabulary", systemImage: "checkmark").font(.caption).foregroundStyle(palette.muted) }
                Spacer()
                Button("Edit Definition…") { editing = true }.buttonStyle(.plain).font(.caption).foregroundStyle(palette.accent)
            }
        }
        .padding(24).frame(maxWidth: 620)
        .background(palette.card, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(palette.outline, lineWidth: 1) }
        .shadow(color: .black.opacity(0.10), radius: 22, y: 8)
        .sheet(isPresented: $editing) {
            DefinitionEditor(entry: entry) { entry in state.definition = entry.stored; state.saveDefinition(dismiss: false); editing = false }
                .environment(\.readingPalette, palette)
        }
    }
}
struct DefinitionEditor: View {
    @Environment(\.dismiss) var dismiss
    let entry: DictionaryEntry
    let save: (DictionaryEntry) -> Void
    @State private var pronunciation = ""
    @State private var origin = ""
    @State private var text = ""
    var body: some View {
        Form { Text(entry.word).font(.title2); TextField("Pronunciation", text: $pronunciation); TextEditor(text: $text).frame(height: 200); TextField("Origin", text: $origin, axis: .vertical); HStack { Button("Cancel") { dismiss() }; Spacer(); Button("Save") { var edited = DictionaryEntry.parse(text, word: entry.word); edited.pronunciation = pronunciation; edited.origin = origin; save(edited) }.keyboardShortcut(.defaultAction) } }.padding(24).frame(width: 500).onAppear { pronunciation = entry.pronunciation; origin = entry.origin; text = entry.senses.map { ($0.partOfSpeech.isEmpty ? "" : "(\($0.partOfSpeech)) ") + $0.gloss }.joined(separator: "\n\n") }
    }
}
/// The same outline geometry as the original Lucide Shield / ShieldCheck icons.
struct SpoilerShield: Shape {
    let checked: Bool
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x*scale, y: rect.minY + y*scale) }
        var p = Path()
        p.move(to: point(12,22)); p.addCurve(to: point(20,12), control1: point(12,22), control2: point(20,18)); p.addLine(to: point(20,5)); p.addLine(to: point(12,2)); p.addLine(to: point(4,5)); p.addLine(to: point(4,12)); p.addCurve(to: point(12,22), control1: point(4,18), control2: point(12,22)); p.closeSubpath()
        if checked { p.move(to: point(9,12)); p.addLine(to: point(11,14)); p.addLine(to: point(15,10)) }
        return p
    }
}
