import SwiftUI
import OpossumKit

struct BuilderView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var status: BuilderStatus?
    @State private var cpus = 4
    @State private var memoryGB = 4
    @State private var isRestarting = false
    @State private var error: String?

    var body: some View {
        Form {
            Section("Build VM") {
                if let status {
                    LabeledContent("State", value: status.state)
                    LabeledContent("Image", value: status.image)
                    LabeledContent("CPUs", value: "\(status.cpus)")
                    LabeledContent("Memory", value: "\(status.memoryMB) MB")
                    if let ip = status.ip { LabeledContent("IP", value: ip) }
                } else {
                    Text("Not running").foregroundStyle(.secondary)
                }
            }

            Section("Resize") {
                Stepper("CPUs: \(cpus)", value: $cpus, in: 1...16)
                Stepper("Memory: \(memoryGB) GB", value: $memoryGB, in: 1...32)
                Button(isRestarting ? "Restarting…" : "Apply (restarts the build VM)") {
                    Task { await restart() }
                }
                .disabled(isRestarting)
                if let error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Builder")
        .task { await refresh() }
    }

    private func refresh() async {
        status = try? await environment.containerCLI.builderStatus()
        if let status { cpus = status.cpus; memoryGB = max(1, status.memoryMB / 1024) }
    }

    private func restart() async {
        isRestarting = true
        error = nil
        defer { isRestarting = false }
        do {
            let result = try await environment.containerCLI.builderRestart(cpus: cpus, memoryGB: memoryGB)
            if !result.succeeded { error = result.stderr }
        } catch {
            self.error = String(describing: error)
        }
        await refresh()
    }
}
