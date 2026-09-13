import SwiftUI
import OpossumKit

/// A table-like row (Docker Desktop's Containers list layout): name/status on the left, fixed-width
/// image/port/status columns, and icon action buttons on the right -- not a `.contextMenu`, so the
/// common actions are visible without a right-click. Column widths must stay in sync with
/// `ContainerRowColumnHeader` in ContainersView.
struct ContainerRow: View {
    let container: ContainerInfo

    var body: some View {
        HStack(spacing: 12) {
            // A NavigationLink whose label is just this leading cell, not the whole row -- the
            // trailing action buttons are its siblings, not nested inside it, so tapping one
            // doesn't also trigger navigation (nesting a Button inside a NavigationLink's label is
            // the pattern that broke click handling for the sidebar; keeping them as siblings here
            // avoids that instead of relying on hit-test luck).
            NavigationLink(value: container) {
                HStack(spacing: 8) {
                    StatusDot(kind: .init(containerState: container.status.state))
                    Text(container.serviceName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(container.configuration.image.reference)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 180, alignment: .leading)

            Group {
                if let port = container.configuration.publishedPorts?.first?.hostPort {
                    Text(":\(port)").font(.caption.monospaced())
                } else {
                    Text("—")
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)

            Text(container.isRunning ? Formatting.duration(since: container.status.startedDate) : container.status.state)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)

            ContainerRowActions(container: container)
                .frame(width: 108, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }
}

private struct ContainerRowActions: View {
    let container: ContainerInfo
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        HStack(spacing: 10) {
            Button { execInTerminal() } label: {
                Image(systemName: "terminal")
            }
            .help("Open a terminal in this container")

            if container.isRunning {
                Button {
                    Task { try? await environment.containerCLI.stop(ids: [container.id]) }
                } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Stop")
            } else {
                Button {
                    Task { try? await environment.containerCLI.start(ids: [container.id]) }
                } label: {
                    Image(systemName: "play.fill")
                }
                .help("Start")
            }

            Menu {
                Button("Restart") { Task { try? await environment.containerCLI.restart(ids: [container.id]) } }
                Button("Kill", role: .destructive) { Task { try? await environment.containerCLI.kill(ids: [container.id]) } }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuIndicator(.hidden)

            Button(role: .destructive) {
                Task { try? await environment.containerCLI.remove(ids: [container.id], force: true) }
            } label: {
                Image(systemName: "trash")
            }
            .help("Remove")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private func execInTerminal() {
        Task {
            guard let projectName = container.projectLabel,
                  let context = await environment.projectContext(for: projectName) else { return }
            let opossumBinary = environment.binaryLocator.locateOpossum() ?? "opossum"
            try? TerminalLauncher.exec(
                project: context,
                service: container.serviceName,
                app: environment.settings.terminalApp,
                opossumBinary: opossumBinary
            )
        }
    }
}
