import SwiftUI
import OpossumKit

struct MenuBarLabel: View {
    @Environment(AppEnvironment.self) private var environment

    private var runningCount: Int {
        environment.runtimeStore.snapshot.containers.filter(\.isRunning).count
    }

    var body: some View {
        let running = environment.runtimeStore.snapshot.runtimeRunning
        Label {
            Text(running ? "\(runningCount)" : "off")
        } icon: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .opacity(running ? 1 : 0.4)
        }
    }
}
