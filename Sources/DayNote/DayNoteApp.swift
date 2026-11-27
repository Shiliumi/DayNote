import SwiftUI

@main
struct DayNoteApp: App {
    @StateObject private var store = TaskStore()

    var body: some Scene {
        WindowGroup("DayNote") {
            ContentView(store: store)
                .frame(minWidth: 340, idealWidth: 370, minHeight: 460, idealHeight: 560)
        }
        .defaultSize(width: 370, height: 560)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
