import SwiftUI
import OpossumKit

struct NetworksView: View {
    let searchText: String
    @Environment(AppEnvironment.self) private var environment
    @State private var selection = Set<String>()

    private var networks: [NetworkInfo] {
        let all = environment.runtimeStore.snapshot.networks
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.configuration.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func attachedContainers(_ network: NetworkInfo) -> Int {
        environment.runtimeStore.snapshot.containers.filter { container in
            container.status.networks?.contains { $0.network == network.configuration.name } ?? false
        }.count
    }

    var body: some View {
        Group {
            if networks.isEmpty {
                EmptyStateView(systemImage: "network", title: "No networks")
            } else {
                Table(networks, selection: $selection) {
                    TableColumn("Name") { network in Text(network.configuration.name).font(.system(.body, design: .monospaced)) }
                    TableColumn("Mode") { network in Text(network.configuration.mode) }
                    TableColumn("Subnet") { network in Text(network.status?.ipv4Subnet ?? "—") }
                    TableColumn("Gateway") { network in Text(network.status?.ipv4Gateway ?? "—") }
                    TableColumn("Attached") { network in Text("\(attachedContainers(network))") }
                }
            }
        }
        .navigationTitle("Networks")
        .toolbar {
            if !selection.isEmpty {
                Button("Delete", role: .destructive) {
                    Task {
                        _ = try? await environment.containerCLI.networkDelete(names: Array(selection))
                        selection.removeAll()
                    }
                }
            }
        }
    }
}
