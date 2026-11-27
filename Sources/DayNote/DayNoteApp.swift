import SwiftUI

@main
struct DayNoteApp: App {
    @NSApplicationDelegateAdaptor(DayNoteAppDelegate.self) private var appDelegate
    @StateObject private var store: TaskStore
    @StateObject private var controller: AppController

    init() {
        let store = TaskStore()
        let controller = AppController()
        controller.attach(store: store)
        _store = StateObject(wrappedValue: store)
        _controller = StateObject(wrappedValue: controller)
    }

    var body: some Scene {
        Window("今日便笺", id: "main") {
            ContentView(store: store, controller: controller, clock: controller.clock)
        }
        .defaultSize(width: 384, height: 610)
        .windowStyle(.hiddenTitleBar)
    }
}
