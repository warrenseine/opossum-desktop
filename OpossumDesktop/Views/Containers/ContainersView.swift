import SwiftUI
import OpossumKit

struct ContainersView: View {
    let searchText: String
    @Environment(AppEnvironment.self) private var environment

    private var grouped: [(project: String, containers: [ContainerInfo])] {
        let all = environment.runtimeStore.snapshot.containers.filter { container in
            searchText.isEmpty
                || container.serviceName.localizedCaseInsensitiveContains(searchText)
                || container.configuration.image.reference.localizedCaseInsensitiveContains(searchText)
        }
        let groups = Dictionary(grouping: all) { $0.projectLabel ?? "(no project)" }
        return groups.keys.sorted().map { key in (project: key, containers: groups[key]!.sorted { $0.serviceName < $1.serviceName }) }
    }

    var body: some View {
        Group {
            if environment.runtimeStore.snapshot.containers.isEmpty {
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: environment.runtimeStore.snapshot.runtimeRunning ? "No containers" : "Runtime stopped",
                    message: environment.runtimeStore.snapshot.runtimeRunning
                        ? "Bring a project up to see its containers here."
                        : "Start the container runtime from the Runtime tab."
                )
            } else {
                List {
                    ForEach(grouped, id: \.project) { group in
                        Section(group.project) {
                            ForEach(group.containers) { container in
                                NavigationLink(value: container) {
                                    ContainerRow(container: container)
                                }
                                .contextMenu { ContainerContextMenu(container: container) }
                            }
                        }
                    }
                }
                .navigationDestination(for: ContainerInfo.self) { container in
                    ContainerDetailView(container: container)
                }
            }
        }
        .navigationTitle("Containers")
    }
}

struct ContainerContextMenu: View {
    let container: ContainerInfo
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if container.isRunning {
            Button("Stop") { Task { try? await environment.containerCLI.stop(ids: [container.id]) } }
            Button("Restart") { Task { try? await environment.containerCLI.restart(ids: [container.id]) } }
            Button("Kill") { Task { try? await environment.containerCLI.kill(ids: [container.id]) } }
        } else {
            Button("Start") { Task { try? await environment.containerCLI.start(ids: [container.id]) } }
        }
        Divider()
        Button("Remove", role: .destructive) {
            Task { try? await environment.containerCLI.remove(ids: [container.id], force: true) }
        }
    }
}
