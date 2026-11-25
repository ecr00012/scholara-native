import SwiftUI
import ScholaraCore

@MainActor
final class ChatState: ObservableObject {
    let store: LibraryStore
    let book: Book
    @Published var threads: [Conversation] = []
    @Published var threadID: Int64?
    @Published var messages: [Message] = []
    @Published var draft = ""
    @Published var streaming = ""
    @Published var busy = false
    @Published var error: String?
    @Published var modelID = ""
    @Published var spoilers = true
    @Published var rename = ""
    private var request: Task<Void, Never>?
    init(store: LibraryStore, book: Book) { self.store = store; self.book = book }
    func load(defaultModel: String) {
        do { threads = try store.threads(bookID: book.id); if let first = threads.first { select(first.id) } else { modelID = defaultModel } } catch { self.error = error.localizedDescription }
    }
    func select(_ id: Int64?) {
        guard !busy else { return }; threadID = id; streaming = ""; error = nil
        do {
            if let id, let thread = threads.first(where: { $0.id == id }) { messages = try store.messages(threadID: id); modelID = thread.model; spoilers = thread.spoilerMode; rename = thread.title }
            else { messages = []; spoilers = true; rename = "New conversation" }
        } catch { self.error = error.localizedDescription }
    }
    func saveThreadSettings() {
        guard let id = threadID else { return }
        do { try store.updateThread(id, title: rename, model: modelID, spoilers: spoilers); threads = try store.threads(bookID: book.id) } catch { self.error = error.localizedDescription }
    }
    func deleteThread() {
        guard let id = threadID, !busy else { return }
        do { try store.deleteThread(id); threads = try store.threads(bookID: book.id); select(threads.first?.id) } catch { self.error = error.localizedDescription }
    }
    func send(reader: ReaderState, config: ModelConfiguration) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        do {
            if modelID.isEmpty { modelID = config.selectedModel }
            if threadID == nil { rename = String(text.prefix(65)); threadID = try store.createThread(bookID: book.id, title: rename, model: modelID) }
            guard let id = threadID else { return }
            saveThreadSettings()
            try store.addMessage(threadID: id, role: "user", text: text)
            messages = try store.messages(threadID: id); draft = ""; streaming = ""; busy = true; error = nil
            let option = config.models.first { $0.id == modelID } ?? ModelOption(id: modelID, name: modelID, supportsTools: false)
            let context = ChatContext(book: book, position: reader.position, pageText: reader.pageText, spoilerMode: spoilers)
            let history = messages; let store = store
            request = Task {
                var latest = ""; var lastUpdate = Date.distantPast
                do {
                    let answer = try await OpenRouter.respond(context: context, history: history, model: option, store: store) { answer in
                        await MainActor.run {
                            latest = answer
                            if Date().timeIntervalSince(lastUpdate) > 0.045 { self.streaming = answer; lastUpdate = Date() }
                        }
                    }
                    try store.addMessage(threadID: id, role: "assistant", text: answer)
                    if UserDefaults.standard.object(forKey: "rememberStudyFocus") as? Bool ?? true {
                        for scope in ["global", "book:\(self.book.id)"] {
                            let existing = try store.profile(scope: scope)
                            let lines = (existing.components(separatedBy: "\n") + ["Recent study question: " + String(text.prefix(300))]).filter { !$0.isEmpty }.suffix(8)
                            try store.saveProfile(scope: scope, text: lines.joined(separator: "\n"))
                        }
                    }
                } catch {
                    let cancelled = Task.isCancelled || error is CancellationError
                    self.error = cancelled ? "Response stopped." : error.localizedDescription
                    if !latest.isEmpty { try? store.addMessage(threadID: id, role: "assistant", text: latest + "\n\n[Incomplete — " + (cancelled ? "stopped" : "connection or model error") + "]") }
                }
                self.streaming = ""; self.busy = false; self.request = nil
                do { self.messages = try store.messages(threadID: id); self.threads = try store.threads(bookID: self.book.id) } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription; busy = false }
    }
    func stop() { request?.cancel() }
}
struct ChatView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.readingPalette) private var palette
    @ObservedObject var state: ReaderState
    @StateObject private var chat: ChatState
    @State private var showRename = false
    @State private var confirmDelete = false
    init(state: ReaderState) { self.state = state; _chat = StateObject(wrappedValue: ChatState(store: state.store, book: state.book)) }
    var book: Book { model.books.first { $0.id == state.book.id } ?? state.book }
    var enabled: Bool { book.indexStatus == "ready" && model.indexProgress[book.id] == nil }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles").foregroundStyle(.orange)
                Text("Agent Scholar").font(.headline)
                Spacer()
                Menu {
                    Button("New Conversation") { chat.select(nil) }
                    ForEach(chat.threads) { thread in Button(thread.title) { chat.select(thread.id) } }
                    if chat.threadID != nil { Divider(); Button("Rename Conversation…") { showRename = true }; Button("Delete Conversation…", role: .destructive) { confirmDelete = true } }
                } label: { Image(systemName: "bubble.left.and.bubble.right") }.disabled(chat.busy).help("Conversations")
            }.padding(.horizontal, 16).padding(.vertical, 10)
            if !enabled {
                VStack(spacing: 16) {
                    Spacer(); Image(systemName: "books.vertical.circle").font(.system(size: 44)).foregroundStyle(.orange)
                    Text("A conversation with your book").font(.headline)
                    Text("Embed this book locally to let Agent Scholar retrieve relevant passages.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let progress = model.indexProgress[book.id] {
                        ProgressView(value: progress); Text(progress == 0 ? "Queued for embedding…" : "Embedding \(Int(progress * 100))%").font(.caption); Button("Cancel") { model.cancelIndex(book.id) }
                    } else { Button("Embed to Enable Agent Scholar") { model.embed(book) }.buttonStyle(.borderedProminent) }
                    if !book.indexError.isEmpty { Text(book.indexError).font(.caption).foregroundStyle(.secondary) }
                    Text("Reading is always available. Embedding stays on your Mac; chat sends selected context to OpenRouter.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Spacer()
                }.padding(24)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Model", selection: $chat.modelID) {
                        ForEach(model.config.models) { option in Text(option.name).tag(option.id) }
                        if !chat.modelID.isEmpty && !model.config.models.contains(where: { $0.id == chat.modelID }) { Text(chat.modelID).tag(chat.modelID) }
                    }.labelsHidden().disabled(chat.busy)
                    Button { chat.spoilers.toggle() } label: {
                        HStack(spacing: 8) {
                            SpoilerShield(checked: chat.spoilers).stroke(chat.spoilers ? palette.accent : palette.muted, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)).frame(width: 19, height: 22)
                            Text(chat.spoilers ? "No spoilers beyond this position" : "Spoilers allowed").font(.caption).foregroundStyle(palette.muted)
                        }
                    }.buttonStyle(.plain).disabled(chat.busy).accessibilityLabel("Avoid spoilers").accessibilityValue(chat.spoilers ? "On" : "Off").help(chat.spoilers ? "Search stays at or before your current position" : "Search can use the full book")
                    if chat.threadID != nil { Text(chat.rename).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                }.padding(.horizontal, 16).padding(.bottom, 10)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            if chat.messages.isEmpty { Text("Ask about an argument, unpack a passage, or connect ideas across the book.").foregroundStyle(.secondary).padding(.vertical, 30) }
                            ForEach(chat.messages) { message in messageView(role: message.role, text: message.text).id(message.id) }
                            if chat.busy { if chat.streaming.isEmpty { ProgressView("Thinking…").controlSize(.small) } else { messageView(role: "assistant", text: chat.streaming) } }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(16)
                    }.onChange(of: chat.messages.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }.onChange(of: chat.streaming) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                }
                if let error = chat.error { Text(error).font(.caption).foregroundStyle(.orange).padding(.horizontal, 14).padding(.vertical, 8).textSelection(.enabled) }
                Divider()
                VStack(spacing: 8) {
                    TextField("Ask about this book…", text: $chat.draft, axis: .vertical).textFieldStyle(.plain).lineLimit(2...6).onSubmit { send() }.disabled(chat.busy)
                    HStack { Text("Context sent to OpenRouter").font(.caption2).foregroundStyle(.secondary); Spacer(); if chat.busy { Button("Stop", systemImage: "stop.fill") { chat.stop() } } else { Button { send() } label: { Image(systemName: "arrow.up") }.buttonStyle(.borderedProminent).keyboardShortcut(.return, modifiers: .command).disabled(chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) } }
                }.padding(14)
            }
        }
        .onAppear { chat.load(defaultModel: model.config.selectedModel) }
        .onDisappear { chat.stop() }
        .onChange(of: chat.modelID) { _, _ in chat.saveThreadSettings() }
        .onChange(of: chat.spoilers) { _, _ in chat.saveThreadSettings() }
        .alert("Rename Conversation", isPresented: $showRename) { TextField("Title", text: $chat.rename); Button("Save") { chat.saveThreadSettings() }; Button("Cancel", role: .cancel) {} }
        .confirmationDialog("Delete this conversation?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { chat.deleteThread() } }
    }
    func send() { guard enabled else { return }; chat.send(reader: state, config: model.config) }
    func messageView(role: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(role == "user" ? "YOU" : "SCHOLAR").font(.caption2.weight(.bold)).foregroundStyle(role == "user" ? Color.secondary : Color.orange); Text(.init(text)).textSelection(.enabled).font(.callout).lineSpacing(4) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
