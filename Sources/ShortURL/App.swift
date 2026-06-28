import SwiftUI

@main
struct ShortURLApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
                .background(.ultraThinMaterial)
                .frame(minWidth: 360, maxWidth: 360, minHeight: 216, maxHeight: 216)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 216)
        .windowStyle(.hiddenTitleBar)
    }
}
