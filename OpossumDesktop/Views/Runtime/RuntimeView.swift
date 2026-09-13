import SwiftUI
import OpossumKit

struct RuntimeView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var diskUsage: [DiskUsageRow] = []
    @State private var isBusy = false
    @State private var actionError: String?
    @State private var systemLogText = ""

    private var running: Bool { environment.runtimeStore.snapshot.runtimeRunning }

    var body: some View {
        Form {
            Section("Container system") {
                HStack {
                    StatusDot(kind: running ? .running : .stopped)
                    Text(running ? "Running" : "Stopped")
                    Spacer()
                    if isBusy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button(running ? "Stop" : "Start") { Task { await toggleRuntime() } }
                    }
                }
                if let actionError {
                    Text(actionError).foregroundStyle(.red).font(.caption)
                }
            }

            Section("Disk usage") {
                if diskUsage.isEmpty {
                    Text("Not loaded").foregroundStyle(.secondary)
                } else {
                    ForEach(diskUsage) { row in
                        LabeledContent(row.type) {
                            Text("\(row.active)/\(row.total) active · \(Formatting.bytes(row.sizeBytes)) · \(Formatting.bytes(row.reclaimableBytes)) reclaimable (\(row.reclaimablePercent)%)")
                                .font(.caption)
                        }
                    }
                }
                Button("Refresh") { Task { await refreshDiskUsage() } }
            }

            Section("Doctor") {
                if let error = environment.doctorError {
                    Text(error).foregroundStyle(.red).font(.caption)
                } else if let report = environment.doctorReport {
                    ForEach(report.checks) { check in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                StatusDot(kind: check.level == .ok ? .running : (check.level == .warn ? .warning : .stopped))
                                Text(check.name).font(.body.weight(.medium))
                            }
                            Text(check.message).font(.caption).foregroundStyle(.secondary)
                            if let fix = check.fix {
                                Text(fix).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text("Not loaded").foregroundStyle(.secondary)
                }
                Button("Re-run doctor") { Task { await environment.refreshDoctor() } }
            }

            Section("System logs (last 5m)") {
                if systemLogText.isEmpty {
                    Button("Load") { Task { await loadSystemLogs() } }
                } else {
                    ScrollView {
                        Text(systemLogText)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 200)
                    Button("Reload") { Task { await loadSystemLogs() } }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Runtime")
        .task {
            await refreshDiskUsage()
        }
    }

    private func toggleRuntime() async {
        isBusy = true
        actionError = nil
        defer { isBusy = false }
        do {
            let result = running
                ? try await environment.containerCLI.systemStop()
                : try await environment.containerCLI.systemStart()
            if !result.succeeded { actionError = result.stderr }
        } catch {
            actionError = String(describing: error)
        }
        environment.runtimeStore.refreshNow()
    }

    private func refreshDiskUsage() async {
        diskUsage = (try? await environment.containerCLI.diskUsage()) ?? []
    }

    private func loadSystemLogs() async {
        var lines: [String] = []
        if let events = try? await collect(environment.containerCLI.systemLogs(follow: false, last: "5m")) {
            for case .stdout(let line) in events { lines.append(line) }
        }
        systemLogText = lines.suffix(500).joined(separator: "\n")
    }

    private func collect(_ stream: AsyncThrowingStream<ProcessEvent, Error>) async throws -> [ProcessEvent] {
        var events: [ProcessEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }
}
