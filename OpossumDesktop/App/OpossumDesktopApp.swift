import SwiftUI
import OpossumKit

@main
struct OpossumDesktopApp: App {
    @State private var environment = AppEnvironment()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(environment)
                .frame(minWidth: 900, minHeight: 560)
                .task { environment.start() }
                .onChange(of: scenePhase) { _, phase in
                    environment.runtimeStore.setVisible(phase == .active)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContentView()
                .environment(environment)
        } label: {
            MenuBarLabel()
                .environment(environment)
        }
        .menuBarExtraStyle(.window)
    }
}
