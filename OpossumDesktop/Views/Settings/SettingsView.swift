import SwiftUI
import OpossumKit

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isRelocateImporterPresented = false
    @State private var relocateTarget: RegisteredProject?
    @State private var isCheckingUpdate = false

    var body: some View {
        @Bindable var environment = environment
        Form {
            Section("Terminal") {
                Picker("Open exec sessions in", selection: $environment.settings.terminalApp) {
                    ForEach(TerminalApp.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .onChange(of: environment.settings.terminalApp) { _, _ in environment.settings.save() }
            }

            Section("Startup") {
                Toggle("Launch Opossum Desktop at login", isOn: $environment.settings.launchAtLogin)
                    .onChange(of: environment.settings.launchAtLogin) { _, newValue in
                        LoginItemManager.setEnabled(newValue)
                        environment.settings.save()
                    }
            }

            Section("Notifications") {
                Toggle("Notify when a running container stops", isOn: $environment.settings.notifyOnContainerExit)
                    .onChange(of: environment.settings.notifyOnContainerExit) { _, _ in environment.settings.save() }
                Toggle("Notify when reclaimable disk usage is high", isOn: $environment.settings.notifyOnDiskReclaimable)
                    .onChange(of: environment.settings.notifyOnDiskReclaimable) { _, _ in environment.settings.save() }
            }

            Section("Registered projects") {
                if environment.registeredProjects.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                } else {
                    ForEach(environment.registeredProjects) { project in
                        HStack {
                            Text(project.name)
                            if project.isOrphaned {
                                Text("folder not found").font(.caption).foregroundStyle(.orange)
                            }
                            Spacer()
                            if project.isOrphaned {
                                Button("Locate…") {
                                    relocateTarget = project
                                    isRelocateImporterPresented = true
                                }
                                .font(.caption)
                            }
                            Button("Remove") { Task { await environment.unregisterProject(name: project.name) } }
                                .font(.caption)
                        }
                    }
                }
            }

            Section("Updates") {
                if let update = environment.availableUpdate {
                    Link("Version \(update.tagName) is available — open release notes", destination: update.htmlURL)
                } else {
                    Text("Opossum Desktop is unsigned; updates ship via Homebrew (`brew upgrade --cask opossum-desktop`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(isCheckingUpdate ? "Checking…" : "Check for updates") {
                    Task {
                        isCheckingUpdate = true
                        await environment.checkForUpdate()
                        isCheckingUpdate = false
                    }
                }
                .disabled(isCheckingUpdate)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .fileImporter(isPresented: $isRelocateImporterPresented, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result, let target = relocateTarget else { return }
            Task {
                await environment.unregisterProject(name: target.name)
                await environment.registerProject(directory: url)
            }
        }
    }
}
