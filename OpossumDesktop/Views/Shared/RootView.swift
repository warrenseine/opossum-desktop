import SwiftUI

enum SidebarSection: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case containers = "Containers"
    case images = "Images"
    case volumes = "Volumes"
    case networks = "Networks"
    case builder = "Builder"
    case runtime = "Runtime"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .projects: "folder.badge.gearshape"
        case .containers: "shippingbox"
        case .images: "square.stack.3d.up"
        case .volumes: "internaldrive"
        case .networks: "network"
        case .builder: "hammer"
        case .runtime: "gauge.with.dots.needle.67percent"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selection: SidebarSection? = .projects
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            List(SidebarSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
        } detail: {
            NavigationStack {
                detailView
                    .searchable(text: $searchText, placement: .toolbar)
            }
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                RuntimeStatusBadge()
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .projects {
        case .projects: ProjectsView(searchText: searchText)
        case .containers: ContainersView(searchText: searchText)
        case .images: ImagesView(searchText: searchText)
        case .volumes: VolumesView(searchText: searchText)
        case .networks: NetworksView(searchText: searchText)
        case .builder: BuilderView()
        case .runtime: RuntimeView()
        case .settings: SettingsView()
        }
    }
}

struct RuntimeStatusBadge: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let running = environment.runtimeStore.snapshot.runtimeRunning
        HStack(spacing: 6) {
            StatusDot(kind: running ? .running : .stopped)
            Text(running ? "Running" : "Stopped")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }
}
