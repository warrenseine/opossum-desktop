import SwiftUI
import OpossumKit

struct ProjectsView: View {
    let searchText: String
    @Environment(AppEnvironment.self) private var environment
    @State private var isImporterPresented = false
    @State private var importError: String?

    private var filtered: [RegisteredProject] {
        let projects = environment.registeredProjects
        guard !searchText.isEmpty else { return projects }
        return projects.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        Group {
            if environment.registeredProjects.isEmpty {
                EmptyStateView(
                    systemImage: "folder.badge.plus",
                    title: "No projects yet",
                    message: "Open a folder containing a compose.yaml to register it.",
                    actionTitle: "Open Folder…"
                ) { isImporterPresented = true }
            } else {
                List(filtered) { project in
                    NavigationLink(value: project) {
                        ProjectRow(project: project)
                    }
                }
                .navigationDestination(for: RegisteredProject.self) { project in
                    ProjectDetailView(project: project)
                }
            }
        }
        .navigationTitle("Projects")
        .toolbar {
            ToolbarItem {
                Button {
                    isImporterPresented = true
                } label: {
                    Label("Open Folder…", systemImage: "folder.badge.plus")
                }
            }
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.folder]) { result in
            handleImport(result)
        }
        .alert("Couldn't register project", isPresented: .constant(importError != nil), presenting: importError) { _ in
            Button("OK") { importError = nil }
        } message: { message in
            Text(message)
        }
        .task { await environment.refreshProjects() }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importError = String(describing: error)
        case .success(let url):
            Task {
                let outcome = await environment.registerProject(directory: url)
                if case .failure(let error) = outcome {
                    importError = String(describing: error)
                }
            }
        }
    }
}

struct ProjectRow: View {
    let project: RegisteredProject
    @Environment(AppEnvironment.self) private var environment
    @State private var runner = ProjectActionRunner()
    @State private var isActionSheetPresented = false

    private var containers: [ContainerInfo] { environment.containers(forProject: project.name) }
    private var runningCount: Int { containers.filter(\.isRunning).count }
    private var isRunning: Bool { runningCount > 0 }

    var body: some View {
        HStack {
            StatusDot(kind: project.isOrphaned ? .warning : (isRunning ? .running : .stopped))
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.body.weight(.medium))
                Text(project.isOrphaned ? "Folder not found" : "\(runningCount)/\(containers.count) running")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if runner.isRunning {
                ProgressView().controlSize(.small)
            } else if !project.isOrphaned {
                Button(isRunning ? "Down" : "Up") {
                    isActionSheetPresented = true
                    Task { await toggle() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $isActionSheetPresented) {
            StreamingActionSheet(title: project.name, runner: runner) { isActionSheetPresented = false }
        }
    }

    private func toggle() async {
        guard let context = await environment.projectContext(for: project.name) else { return }
        if isRunning {
            runner.run(label: "down", stream: environment.opossumCLI.down(context))
        } else {
            runner.run(label: "up", stream: environment.opossumCLI.up(context, build: false))
        }
    }
}
