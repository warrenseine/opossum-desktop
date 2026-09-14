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
        // Not .contentSize: it tracks the content's ideal size with no upper bound, and a
        // ScrollView full of rows (e.g. Containers with many services) reports its full content
        // height as "ideal", so the window kept growing to fit every row instead of scrolling --
        // balloons to 1000pt+ tall just from switching to a busy project. .automatic (the
        // default) makes it a normal user-resizable window instead.
        .windowResizability(.automatic)
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
