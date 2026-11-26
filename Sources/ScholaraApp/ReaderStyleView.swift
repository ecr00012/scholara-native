import SwiftUI
import ScholaraCore

struct ReaderStyleView: View {
    let isPDF: Bool
    @Environment(\.dismiss) private var dismiss
    @AppStorage("readingPalette") private var paletteName = "Soft"
    @AppStorage("readerFontFamily") private var fontFamily = ReaderFont.serif.rawValue
    @AppStorage("readerFontSize") private var fontSize = 19.0
    private var palette: ReadingPalette { ReadingPalette(rawValue: paletteName) ?? .soft }
    private var font: ReaderFont { ReaderFont(rawValue: fontFamily) ?? .serif }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Style").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance").font(.headline)
                Picker("Appearance", selection: $paletteName) {
                    ForEach(ReadingPalette.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }.pickerStyle(.segmented).labelsHidden()
            }
            Picker("Font", selection: $fontFamily) {
                ForEach(ReaderFont.allCases) { Text($0.rawValue).tag($0.rawValue) }
            }.disabled(isPDF)
            VStack(alignment: .leading, spacing: 6) {
                Text("Font size · \(Int(fontSize)) pt").font(.callout)
                Slider(value: $fontSize, in: 13...32, step: 1).accessibilityLabel("Font size")
            }.disabled(isPDF)
            VStack(alignment: .leading, spacing: 10) {
                Text("A moment to read").font(Font(font.font(size: fontSize * 1.2)))
                Text("There is a quiet pleasure in opening a book and discovering a world within its pages.")
                    .font(Font(font.font(size: fontSize))).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading).padding(20)
                .background(palette.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).stroke(palette.outline, lineWidth: 1) }
            if isPDF { Text("PDF pages retain their original typography. Use zoom to adjust their size.").font(.caption).foregroundStyle(palette.muted) }
        }.padding(24).frame(width: 380).foregroundStyle(palette.ink).background(palette.surface)
            .preferredColorScheme(palette.colorScheme)
    }
}
