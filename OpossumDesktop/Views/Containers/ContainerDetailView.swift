import SwiftUI
import Charts
import OpossumKit

struct ContainerDetailView: View {
    let container: ContainerInfo
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab: Tab = .logs
    @State private var logStreamer = LogStreamer()

    enum Tab: String, CaseIterable, Identifiable {
        case logs = "Logs", inspect = "Inspect", stats = "Stats", mounts = "Mounts"
        var id: String { rawValue }
    }

    /// Look up the freshest copy from the store — the one passed in is a snapshot from whenever
    /// navigation happened, and fields like state/IP change underneath it.
    private var current: ContainerInfo {
        environment.runtimeStore.snapshot.containers.first { $0.id == container.id } ?? container
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            Group {
                switch selectedTab {
                case .logs: ContainerLogsTab(logStreamer: logStreamer)
                case .inspect: ContainerInspectTab(container: current)
                case .stats: ContainerStatsTab(container: current)
                case .mounts: ContainerMountsTab(container: current)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(current.serviceName)
        .toolbar {
            ToolbarItemGroup {
                Button("Exec…") { execInTerminal() }
                if current.isRunning {
                    Button("Stop") { Task { try? await environment.containerCLI.stop(ids: [current.id]) } }
                } else {
                    Button("Start") { Task { try? await environment.containerCLI.start(ids: [current.id]) } }
                }
            }
        }
        .onAppear {
            logStreamer.start(containerID: current.id)
            environment.statsSampler.updateCPUAllotment(from: environment.runtimeStore.snapshot.containers)
            environment.statsSampler.watch(ids: [current.id])
        }
        .onDisappear {
            logStreamer.stop()
            environment.statsSampler.watch(ids: [])
        }
    }

    private func execInTerminal() {
        Task {
            guard let projectName = current.projectLabel,
                  let context = await environment.projectContext(for: projectName) else { return }
            let opossumBinary = environment.binaryLocator.locateOpossum() ?? "opossum"
            try? TerminalLauncher.exec(
                project: context,
                service: current.serviceName,
                app: environment.settings.terminalApp,
                opossumBinary: opossumBinary
            )
        }
    }
}

private struct ContainerLogsTab: View {
    @Bindable var logStreamer: LogStreamer

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if logStreamer.isStreaming {
                    Label("Following", systemImage: "dot.radiowaves.left.and.right").font(.caption).foregroundStyle(.secondary)
                }
                if let error = logStreamer.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Spacer()
                Button("Clear") { logStreamer.clear() }
                    .font(.caption)
            }
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(logStreamer.lines.enumerated()), id: \.offset) { index, line in
                            Text(line.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(line.stream == .stderr ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .onChange(of: logStreamer.lines.count) { _, count in
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }
}

private struct ContainerInspectTab: View {
    let container: ContainerInfo
    @State private var revealed: Set<String> = []

    private var envEntries: [Masker.EnvEntry] {
        Masker.parseEnvironment(container.configuration.initProcess?.environment ?? [])
    }

    var body: some View {
        Form {
            Section("Image") {
                LabeledContent("Reference", value: container.configuration.image.reference)
                LabeledContent("CPUs", value: "\(container.configuration.resources.cpus)")
                LabeledContent("Memory", value: Formatting.bytes(container.configuration.resources.memoryInBytes))
            }
            if let labels = container.configuration.labels, !labels.isEmpty {
                Section("Labels") {
                    ForEach(labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }
            if !envEntries.isEmpty {
                Section("Environment") {
                    ForEach(envEntries) { entry in
                        HStack {
                            Text(entry.key).font(.system(.body, design: .monospaced))
                            Spacer()
                            Text(revealed.contains(entry.key) ? entry.value : entry.displayValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            if entry.isSensitive {
                                Button(revealed.contains(entry.key) ? "Hide" : "Reveal") {
                                    if revealed.contains(entry.key) { revealed.remove(entry.key) } else { revealed.insert(entry.key) }
                                }
                                .font(.caption)
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ContainerStatsTab: View {
    let container: ContainerInfo
    @Environment(AppEnvironment.self) private var environment

    private var points: [StatsPoint] { environment.statsSampler.history[container.id] ?? [] }

    var body: some View {
        Form {
            Section("CPU % (of allotted \(container.configuration.resources.cpus) CPU\(container.configuration.resources.cpus == 1 ? "" : "s"))") {
                Chart(points) { point in
                    LineMark(x: .value("Time", point.timestamp), y: .value("CPU %", point.cpuPercent ?? 0))
                }
                .chartYScale(domain: 0...max(100, (points.compactMap(\.cpuPercent).max() ?? 100)))
                .frame(height: 120)
            }
            Section("Memory") {
                Chart(points) { point in
                    LineMark(x: .value("Time", point.timestamp), y: .value("Memory", Double(point.memoryUsageBytes) / 1_048_576))
                }
                .frame(height: 120)
                if let last = points.last {
                    LabeledContent("Used", value: "\(Formatting.bytes(last.memoryUsageBytes)) / \(Formatting.bytes(last.memoryLimitBytes))")
                }
            }
            if let last = points.last {
                Section("Network / Disk") {
                    LabeledContent("Rx / Tx", value: "\(Formatting.bytes(last.networkRxBytes)) / \(Formatting.bytes(last.networkTxBytes))")
                    LabeledContent("Block Read / Write", value: "\(Formatting.bytes(last.blockReadBytes)) / \(Formatting.bytes(last.blockWriteBytes))")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ContainerMountsTab: View {
    let container: ContainerInfo

    var body: some View {
        Form {
            if let mounts = container.configuration.mounts, !mounts.isEmpty {
                ForEach(mounts) { mount in
                    Section(mount.destination) {
                        LabeledContent("Source", value: mount.source)
                        LabeledContent("Kind", value: mount.type.kind)
                        if mount.type.kind == "bind" {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: mount.source)])
                            }
                        }
                    }
                }
            } else {
                Text("No mounts").foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
