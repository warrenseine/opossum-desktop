import SwiftUI
import OpossumKit

struct MenuBarContentView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if environment.registeredProjects.isEmpty {
                Text("No projects registered yet.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(environment.registeredProjects) { project in
                            MenuBarProjectRow(project: project)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 260)
            }
            Divider()
            footer
        }
        .frame(width: 300)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            StatusDot(kind: environment.runtimeStore.snapshot.runtimeRunning ? .running : .stopped)
            Text(environment.runtimeStore.snapshot.runtimeRunning ? "Runtime running" : "Runtime stopped")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        HStack {
            Button("Open Opossum Desktop") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .keyboardShortcut("o")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

private struct MenuBarProjectRow: View {
    let project: RegisteredProject
    @Environment(AppEnvironment.self) private var environment
    @State private var runner = ProjectActionRunner()

    private var isRunning: Bool {
        !environment.containers(forProject: project.name).filter(\.isRunning).isEmpty
    }

    var body: some View {
        HStack {
            StatusDot(kind: isRunning ? .running : .stopped)
            Text(project.name)
                .lineLimit(1)
            Spacer()
            if runner.isRunning {
                ProgressView().controlSize(.small)
            } else {
                Button(isRunning ? "Stop" : "Start") {
                    Task { await toggle() }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }

    private func toggle() async {
        guard let context = await environment.projectContext(for: project.name) else { return }
        if isRunning {
            runner.run(label: "down", stream: environment.opossumCLI.down(context), notifyProject: project.name)
        } else {
            runner.run(label: "up", stream: environment.opossumCLI.up(context), notifyProject: project.name)
        }
    }
}
