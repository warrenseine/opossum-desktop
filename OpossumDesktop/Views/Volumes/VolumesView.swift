import SwiftUI
import OpossumKit

struct VolumesView: View {
    let searchText: String
    @Environment(AppEnvironment.self) private var environment
    @State private var selection = Set<String>()

    private var volumes: [VolumeInfo] {
        let all = environment.runtimeStore.snapshot.volumes
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.configuration.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func usedBy(_ volume: VolumeInfo) -> [ContainerInfo] {
        environment.runtimeStore.snapshot.containers.filter { container in
            container.configuration.mounts?.contains { $0.type.kind == "volume" && $0.source.contains(volume.configuration.name) } ?? false
        }
    }

    var body: some View {
        Group {
            if volumes.isEmpty {
                EmptyStateView(systemImage: "internaldrive", title: "No volumes", message: "Volumes created by projects show up here.")
            } else {
                Table(volumes, selection: $selection) {
                    TableColumn("Name") { volume in Text(volume.configuration.name).font(.system(.body, design: .monospaced)) }
                    TableColumn("Driver") { volume in Text(volume.configuration.driver) }
                    TableColumn("Used by") { volume in
                        let count = usedBy(volume).count
                        Text(count == 0 ? "unused" : "\(count) container\(count == 1 ? "" : "s")")
                            .foregroundStyle(count == 0 ? .secondary : .primary)
                    }
                    TableColumn("Source") { volume in
                        Text(volume.configuration.source).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .navigationTitle("Volumes")
        .toolbar {
            ToolbarItemGroup {
                Button("Prune unused") { Task { try? await environment.containerCLI.volumePrune() } }
                if !selection.isEmpty {
                    Button("Delete", role: .destructive) {
                        Task {
                            _ = try? await environment.containerCLI.volumeDelete(names: Array(selection))
                            selection.removeAll()
                        }
                    }
                }
            }
        }
    }
}
