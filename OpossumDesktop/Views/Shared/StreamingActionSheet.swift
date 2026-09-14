import SwiftUI
import OpossumKit

/// Shows the live stdout/stderr of a streamed opossum action (`up`, `down`, `destroy`, …), with
/// any `[OPSM-NNN]` diagnostics called out and their canned fix, if one is known.
struct StreamingActionSheet: View {
    let title: String
    @Bindable var runner: ProjectActionRunner
    let onDismiss: () -> Void
    // See ContainerDetailView.ContainerLogsTab.isActive: skips a `scrollTo` that would otherwise
    // collide with this sheet's own dismissal teardown.
    @State private var isActive = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                statusBadge
            }
            .padding()

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(runner.output.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: runner.output.count) { _, count in
                    guard isActive, count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onDisappear { isActive = false }

            if !runner.diagnostics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(runner.diagnostics) { diagnostic in
                        DiagnosticRow(diagnostic: diagnostic)
                    }
                }
                .padding(8)
            }

            Divider()
            HStack {
                Spacer()
                if runner.isRunning {
                    Button("Cancel") { runner.cancel() }
                } else {
                    Button("Close") { onDismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 640, height: 460)
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch runner.state {
        case .idle:
            EmptyView()
        case .running(let label):
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text(label) }
        case .succeeded:
            Label("Done", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(_, let code):
            Label("Failed (exit \(code))", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        }
    }
}

private struct DiagnosticRow: View {
    let diagnostic: OPSMDiagnostic

    private var tint: Color { diagnostic.severity == .info ? .secondary : .orange }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: diagnostic.severity == .info ? "info.circle" : "exclamationmark.triangle")
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(diagnostic.code).font(.caption.bold())
                Text(diagnostic.message).font(.caption)
                if let fix = OPSMCodes.fix(for: diagnostic.code) {
                    Text(fix).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
