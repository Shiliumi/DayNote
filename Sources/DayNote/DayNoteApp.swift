import SwiftUI

@main
struct DayNoteApp: App {
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
        WindowGroup("DayNote") {
            ContentView(store: store, controller: controller)
        }
        .defaultSize(width: 370, height: 560)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        MenuBarExtra {
            MenuBarContentView(store: store, controller: controller)
        } label: {
            MenuBarLabelView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
