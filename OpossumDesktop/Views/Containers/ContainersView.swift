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
                // Not `List` -- on this toolchain, a List grouped into dynamic Sections here
                // renders as nothing but a lone warning-triangle glyph and no title (same category
                // of failure as the sidebar's List click bug and ContentUnavailableView's broken
                // render: see RootView, EmptyStateView). A plain ScrollView has no List/Section
                // machinery to fail; `ProjectsView`'s flat, ungrouped `List` is unaffected, so this
                // is left as the narrower fix rather than replacing List everywhere.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ContainerRowColumnHeader()
                        ForEach(grouped, id: \.project) { group in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.project)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 4)
                                ForEach(group.containers) { container in
                                    ContainerRow(container: container)
                                    Divider()
                                }
                            }
                        }
                    }
                    .padding()
                }
                .navigationDestination(for: ContainerInfo.self) { container in
                    ContainerDetailView(container: container)
                }
            }
        }
        .navigationTitle("Containers")
    }
}

/// Column titles for `ContainerRow`'s layout below -- widths must stay in sync with it.
private struct ContainerRowColumnHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Image").frame(width: 180, alignment: .leading)
            Text("Port").frame(width: 70, alignment: .leading)
            Text("Status").frame(width: 70, alignment: .leading)
            Text("Actions").frame(width: 108, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
    }
}
