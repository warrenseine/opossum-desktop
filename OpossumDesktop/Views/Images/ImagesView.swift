import SwiftUI
import OpossumKit

struct ImagesView: View {
    let searchText: String
    @Environment(AppEnvironment.self) private var environment
    @State private var pullReference = ""
    @State private var isPullSheetPresented = false
    @State private var pullRunner = ProjectActionRunner()
    @State private var selection = Set<String>()

    private var images: [ImageInfo] {
        let all = environment.runtimeStore.snapshot.images
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.reference.localizedCaseInsensitiveContains(searchText) }
    }

    private func usedBy(_ image: ImageInfo) -> [ContainerInfo] {
        environment.runtimeStore.snapshot.containers.filter { $0.configuration.image.reference == image.reference }
    }

    var body: some View {
        Group {
            if images.isEmpty {
                EmptyStateView(systemImage: "square.stack.3d.up", title: "No images", message: "Pull an image or bring a project up to see images here.")
            } else {
                Table(images, selection: $selection) {
                    TableColumn("Reference") { image in Text(image.reference).font(.system(.body, design: .monospaced)) }
                    TableColumn("Size") { image in Text(Formatting.bytes(image.sizeBytes)) }
                    TableColumn("Used by") { image in
                        let count = usedBy(image).count
                        Text(count == 0 ? "unused" : "\(count) container\(count == 1 ? "" : "s")")
                            .foregroundStyle(count == 0 ? .secondary : .primary)
                    }
                }
            }
        }
        .navigationTitle("Images")
        .toolbar {
            ToolbarItemGroup {
                Button("Pull…") { isPullSheetPresented = true }
                Button("Prune dangling") { Task { try? await environment.containerCLI.imagePrune(all: false) } }
                Menu("Prune all…") {
                    Button("Prune unused images", role: .destructive) {
                        Task { try? await environment.containerCLI.imagePrune(all: true) }
                    }
                }
                if !selection.isEmpty {
                    Button("Delete", role: .destructive) {
                        Task {
                            _ = try? await environment.containerCLI.imageDelete(references: Array(selection))
                            selection.removeAll()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isPullSheetPresented) {
            PullImageSheet(reference: $pullReference, runner: pullRunner, isPresented: $isPullSheetPresented)
        }
    }
}

private struct PullImageSheet: View {
    @Binding var reference: String
    @Bindable var runner: ProjectActionRunner
    @Binding var isPresented: Bool
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pull image").font(.headline)
            TextField("docker.io/library/nginx:latest", text: $reference)
                .textFieldStyle(.roundedBorder)
                .disabled(runner.isRunning)
            if !runner.output.isEmpty {
                ScrollView {
                    Text(runner.output.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 160)
                .background(Color(nsColor: .textBackgroundColor))
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button(runner.isRunning ? "Pulling…" : "Pull") {
                    runner.run(label: "pull", stream: environment.containerCLI.imagePull(reference: reference))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(reference.isEmpty || runner.isRunning)
            }
        }
        .padding()
        .frame(width: 460)
    }
}
