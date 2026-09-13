import SwiftUI
import OpossumKit

struct ProjectDetailView: View {
    let project: RegisteredProject
    @Environment(AppEnvironment.self) private var environment

    @State private var runner = ProjectActionRunner()
    @State private var isActionSheetPresented = false
    @State private var configText = ""
    @State private var isLoadingConfig = false
    @State private var isDestroyConfirmationPresented = false
    @State private var removeVolumesOnDown = false

    private var containers: [ContainerInfo] { environment.containers(forProject: project.name) }

    var body: some View {
        Form {
            Section("Containers") {
                if containers.isEmpty {
                    Text("No containers for this project yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(containers.sorted { $0.serviceName < $1.serviceName }) { container in
                        NavigationLink(value: container) {
                            ContainerRow(container: container)
                        }
                    }
                }
            }

            Section("Actions") {
                HStack(spacing: 8) {
                    Button("Up") { runAction(label: "up") { environment.opossumCLI.up($0) } }
                    Button("Up --build") { runAction(label: "up --build") { environment.opossumCLI.up($0, build: true) } }
                    Button("Down") { runAction(label: "down") { environment.opossumCLI.down($0, removeVolumes: removeVolumesOnDown) } }
                    Button("Restart") { runAction(label: "restart") { environment.opossumCLI.restart($0) } }
                }
                Toggle("Remove named volumes on Down (-v)", isOn: $removeVolumesOnDown)
            }

            Section("Compose files") {
                ForEach(project.composeFiles, id: \.self) { file in
                    Text(file).font(.system(.body, design: .monospaced))
                }
                Button("Reveal in Finder") { revealInFinder() }
            }

            Section("Resolved config") {
                if isLoadingConfig {
                    ProgressView()
                } else if configText.isEmpty {
                    Text("Not loaded").foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        Text(configText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 220)
                }
                Button("Reload") { Task { await loadConfig() } }
            }

            Section("Danger zone") {
                Button("Destroy project…", role: .destructive) { isDestroyConfirmationPresented = true }
                Button("Remove from Opossum Desktop (keeps it on disk)") {
                    Task { await environment.unregisterProject(name: project.name) }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(project.name)
        .navigationDestination(for: ContainerInfo.self) { container in
            ContainerDetailView(container: container)
        }
        .task { await loadConfig() }
        .sheet(isPresented: $isActionSheetPresented) {
            StreamingActionSheet(title: project.name, runner: runner) { isActionSheetPresented = false }
        }
        .confirmationDialog(
            "Destroy \(project.name)?",
            isPresented: $isDestroyConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Destroy", role: .destructive) { destroy() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every container, network, and (unless kept) volume opossum created for this project. This can't be undone.")
        }
    }

    private func runAction(label: String, action: @escaping (ProjectContext) -> AsyncThrowingStream<ProcessEvent, Error>) {
        Task {
            guard let context = await environment.projectContext(for: project.name) else { return }
            isActionSheetPresented = true
            runner.run(label: label, stream: action(context))
        }
    }

    private func destroy() {
        Task {
            guard let context = await environment.projectContext(for: project.name) else { return }
            isActionSheetPresented = true
            runner.run(label: "destroy", stream: environment.opossumCLI.destroy(context))
        }
    }

    private func loadConfig() async {
        guard let context = await environment.projectContext(for: project.name) else { return }
        isLoadingConfig = true
        defer { isLoadingConfig = false }
        if let result = try? await environment.opossumCLI.config(for: context) {
            configText = result.succeeded ? result.stdout : result.stderr
        }
    }

    private func revealInFinder() {
        Task {
            guard let context = await environment.projectContext(for: project.name) else { return }
            await MainActor.run {
                NSWorkspace.shared.activateFileViewerSelecting([context.directory])
            }
        }
    }
}
