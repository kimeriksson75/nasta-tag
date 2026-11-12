import SwiftUI

@main
struct NastaTagApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .task { model.begin() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.refreshSoon() }
                }
        }
    }
}
