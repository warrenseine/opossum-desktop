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
            // Not List(selection:) -- on this toolchain, clicking a row never updated the
            // selection binding in testing (most likely explanation: List's underlying
            // NSTableView intercepting the click before anything else sees it, a known category
            // of issue on macOS). A plain ScrollView + VStack of rows, with each row setting
            // `selection` itself via .onTapGesture, has no NSTableView underneath to do that, and
            // is confirmed working (verified with real simulated mouse clicks via `cliclick`,
            // which -- unlike osascript/System Events' `click at` -- actually registers with
            // SwiftUI's gesture system on this toolchain).
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SidebarSection.allCases) { section in
                        SidebarRow(section: section, isSelected: section == selection)
                            .contentShape(Rectangle())
                            .onTapGesture { selection = section }
                    }
                }
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 190)
            // Suppresses macOS's automatic keyboard-focus ring, which the system assigns by
            // default to the first focusable control in a new window -- here, whichever sidebar
            // row rendered first. Each row already draws its own selection highlight (the
            // isSelected background), so the system's separate ring on top of that just reads as
            // a second, permanently "focused"-looking row that never goes away.
            .focusEffectDisabled()
        } detail: {
            NavigationStack {
                detailView
            }
        }
        // .searchable and the custom toolbar item both attach here, at the NavigationSplitView
        // itself, rather than splitting .searchable onto the inner NavigationStack -- keep them
        // together regardless: AppKit logs "It's not legal to call -layoutSubtreeIfNeeded on a
        // view which is already being laid out" once, very early at launch, every run. Verified by
        // testing (not assumption) that this specific arrangement is NOT the cause: the warning
        // still fires identically with .searchable removed, and again with the .toolbar removed
        // too. It appears intrinsic to this beta's NavigationSplitView/MenuBarExtra window
        // materialization, logged once by design (see _NSDetectedLayoutRecursion) with no
        // reproducible symptom tied to it after the sidebar/List/ContentUnavailableView fixes
        // elsewhere in this file's history -- not something fixable from application code.
        .searchable(text: $searchText, placement: .toolbar)
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

/// A sidebar row that owns its own selection highlight, since `List(_:selection:)`'s built-in
/// click handling doesn't work on this toolchain (see RootView).
private struct SidebarRow: View {
    let section: SidebarSection
    let isSelected: Bool

    var body: some View {
        Label(section.rawValue, systemImage: section.systemImage)
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
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
