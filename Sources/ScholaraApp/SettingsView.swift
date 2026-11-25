import SwiftUI
import UniformTypeIdentifiers
import ScholaraCore

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    @AppStorage("readingPalette") private var paletteName = "Soft"
    @State private var config = ModelConfiguration.initial
    @State private var key = ""
    @State private var status = ""
    @State private var preferences = ""
    @State private var profile = ""
    @State private var catalogue: [ModelOption] = []
    @State private var catalogueSearch = ""
    @State private var showCatalogue = false
    @State private var busy = false
    @State private var importingLegacy = false
    @AppStorage("readerFontSize") private var fontSize = 19.0
    @AppStorage("rememberStudyFocus") private var rememberStudyFocus = true
    var body: some View {
        TabView {
            Form {
                Section("OpenRouter") {
                    SecureField("API key", text: $key, prompt: Text("Enter a new key to replace the saved key"))
                    HStack {
                        Button("Save Key") { act { try Keychain.save(key); key = ""; status = "API key saved in macOS Keychain." } }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Remove Key", role: .destructive) { act { try Keychain.save(""); status = "API key removed." } }
                        Button("Copy Key from Original Scholara") { act { guard let existing = try Keychain.load(service: "scholara") else { throw ScholaraError("No key was found in the original Scholara Keychain entry.") }; try Keychain.save(existing); status = "Copied to the native app’s Keychain entry. The original is unchanged." } }
                    }
                    Text("Chat sends your messages, relevant book passages, and study context to OpenRouter. Reading and embeddings work locally.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Models") {
                    Picker("Default model", selection: $config.selectedModel) { ForEach(config.models) { Text($0.name.isEmpty ? $0.id : $0.name).tag($0.id) } }
                    ForEach(config.models.indices, id: \.self) { index in
                        let entry = config.models[index]
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) { TextField("Display name", text: $config.models[index].name); TextField("provider/model-path", text: $config.models[index].id).font(.system(.body, design: .monospaced)) }
                            Toggle("Tools", isOn: $config.models[index].supportsTools).toggleStyle(.checkbox).help("Turn off for models that do not support tool calling. Local retrieval still supplies book context.")
                            Button { let id = entry.id; config.models.removeAll { $0.id == id }; if config.selectedModel == id { config.selectedModel = config.models.first?.id ?? "" } } label: { Image(systemName: "minus.circle") }.buttonStyle(.borderless).accessibilityLabel("Remove model")
                        }
                    }
                    HStack {
                        Button("Add Custom Path") { let id = "provider/model-\(config.models.count + 1)"; config.models.append(ModelOption(id: id, name: "Custom model", supportsTools: false)) }
                        Button("Browse OpenRouter Catalogue…") { fetchCatalogue() }.disabled(busy)
                        if busy { ProgressView().controlSize(.small) }
                        Spacer(); Button("Save Models") { act { try model.saveConfig(config); status = "Model configuration saved." } }.buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Button("Reveal models.json") { if let url = model.store?.modelsURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                        Button("Reload File") { act { if let url = model.store?.modelsURL { config = try ModelConfiguration.load(from: url); model.config = config; status = "Reloaded models.json." } } }
                        Button("Import JSON…") { importModels() }
                        Button("Export JSON…") { exportModels() }
                    }
                    Text("Any OpenRouter model path is accepted. Availability and pricing come from OpenRouter; the catalogue is optional. Changes are stored in models.json.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("AI & Models", systemImage: "sparkles") }
            Form {
                Section("Reader") { Picker("Light appearance", selection: $paletteName) { ForEach(ReadingPalette.allCases) { palette in Text(palette.rawValue).tag(palette.rawValue) } }; Text("Paper uses a traditional white palette. Soft uses Scholara’s original warm cream and ink.").font(.caption).foregroundStyle(.secondary); Slider(value: $fontSize, in: 13...32, step: 1) { Text("EPUB font size: \(Int(fontSize))") }; Text("PDF uses native PDFKit selection, zooming, search, and printing. EPUB uses native text layout and the macOS dictionary.").foregroundStyle(.secondary) }
                Section("Study preferences") { TextEditor(text: $preferences).frame(height: 100); Text("Tell Agent Scholar how you prefer explanations, quotations, and discussion.").font(.caption).foregroundStyle(.secondary) }
                Section("Study memory") { Toggle("Remember recent study questions locally", isOn: $rememberStudyFocus); TextEditor(text: $profile).frame(height: 100); Text("Recent questions provide continuity without extra AI calls. You can edit or clear this memory here.").font(.caption).foregroundStyle(.secondary) }
                Button("Save Preferences & Memory") { act { try model.store?.savePreference(scope: "global", text: preferences); try model.store?.saveProfile(scope: "global", text: profile); status = "Preferences saved." } }
            }.formStyle(.grouped).tabItem { Label("Reading", systemImage: "text.book.closed") }
            Form {
                Section("Local library") {
                    Text(model.store?.root.path ?? "Library unavailable").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Button("Show in Finder") { if let root = model.store?.root { NSWorkspace.shared.open(root) } }
                    Text("Back up this folder while Scholara is closed to preserve books, annotations, conversations, model configuration, and embeddings. API keys remain in Keychain.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Import from the original Scholara") {
                    Text("Choose its data folder containing scholara.db. Books and study data are copied into the native library. Exact EPUB text offsets may shift; old embedding vectors are replaced only when you choose Embed.")
                    Button(importingLegacy ? "Importing…" : "Choose Original Data Folder…") { importLegacy() }.disabled(importingLegacy)
                    Text("The original app’s data and source repository are left unchanged.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Embedding") {
                    Text("Each book has its own Embed to Enable Agent Scholar action. Opening a book does not start indexing. One embedding job runs at a time to keep reading responsive.")
                    Text("Apple’s on-device sentence models replace the bundled JavaScript/ONNX pipeline. Language availability depends on macOS; scanned PDFs need OCR.").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).tabItem { Label("Library & Data", systemImage: "externaldrive") }
        }
        .safeAreaInset(edge: .bottom) { if !status.isEmpty { Text(status).font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding().background(.bar) } }
        .onAppear { config = model.config; act { preferences = try model.store?.preference(scope: "global") ?? ""; profile = try model.store?.profile(scope: "global") ?? "" } }
        .sheet(isPresented: $showCatalogue) {
            VStack {
                HStack { Text("OpenRouter Models").font(.title2); Spacer(); Button("Done") { showCatalogue = false } }.padding()
                TextField("Search names or model paths", text: $catalogueSearch).textFieldStyle(.roundedBorder).padding(.horizontal)
                List(catalogue.filter { catalogueSearch.isEmpty || ($0.name + $0.id).localizedCaseInsensitiveContains(catalogueSearch) }) { entry in
                    HStack { VStack(alignment: .leading) { Text(entry.name); Text(entry.id).font(.caption.monospaced()).foregroundStyle(.secondary) }; Spacer(); Button(config.models.contains(where: { $0.id == entry.id }) ? "Added" : "Add") { config.models.append(entry) }.disabled(config.models.contains { $0.id == entry.id }) }
                }
            }.frame(width: 660, height: 500)
        }
    }
    func act(_ action: () throws -> Void) { do { try action() } catch { status = error.localizedDescription } }
    func fetchCatalogue() { busy = true; Task { do { catalogue = try await OpenRouter.availableModels(); showCatalogue = true } catch { status = error.localizedDescription }; busy = false } }
    func importModels() { let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; if panel.runModal() == .OK, let url = panel.url { act { config = try ModelConfiguration.load(from: url); status = "Imported configuration. Choose Save Models to apply." } } }
    func exportModels() { let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "models.json"; if panel.runModal() == .OK, let url = panel.url { act { try config.save(to: url); status = "Model configuration exported." } } }
    func importLegacy() {
        guard let store = model.store else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.message = "Select the original Scholara data folder containing scholara.db."
        panel.directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("com.scholara.desktop")
        guard panel.runModal() == .OK, let url = panel.url else { return }; importingLegacy = true
        Task { do { let report = try await Task.detached { try LegacyImport.run(directory: url, store: store) }.value; model.refresh(); status = "Imported \(report.books) books, \(report.notes) notes, and \(report.messages) messages.\n" + report.warnings.joined(separator: "\n") } catch { status = error.localizedDescription }; importingLegacy = false }
    }
}
