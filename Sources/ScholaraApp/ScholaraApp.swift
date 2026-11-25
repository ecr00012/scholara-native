import SwiftUI
import ScholaraCore

@main
struct ScholaraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @AppStorage("readingPalette") private var paletteName = "Soft"
    private var palette: ReadingPalette { ReadingPalette(rawValue: paletteName) ?? .soft }
    var body: some Scene {
        WindowGroup("Scholara", id: "library") {
            RootView().environmentObject(model).environment(\.readingPalette, palette).preferredColorScheme(.light).frame(minWidth: 960, minHeight: 640)
                .onOpenURL { model.importFiles([$0]) }
        }
        .defaultSize(width: 1360, height: 880)
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Import Books…") { model.chooseBooks() }.keyboardShortcut("o") }
            CommandGroup(after: .sidebar) {
                Button("Library") { model.activeBookID = nil; model.section = .library }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Toggle Agent Scholar") { model.toggleReaderMode() }.keyboardShortcut("\\", modifiers: .command)
            }
        }
        Settings { SettingsView().environmentObject(model).environment(\.readingPalette, palette).preferredColorScheme(.light).frame(width: 760, height: 680) }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.appearance = NSAppearance(named: .aqua); NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
