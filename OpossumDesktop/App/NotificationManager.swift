import Foundation
import UserNotifications
import OpossumKit

/// Thin wrapper over `UNUserNotificationCenter` for the handful of local notifications the app
/// sends. Every call is a no-op until the user has granted authorization.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var isAuthorized = false

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.isAuthorized = granted }
        }
    }

    /// Without this, macOS silently drops notifications posted while the app is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Apple's `container` runtime exposes only a running/stopped state, not an exit code, so
    /// this fires on any running -> stopped transition rather than specifically a non-zero exit.
    func notifyContainerStopped(service: String, project: String?) {
        post(
            title: "Container stopped",
            body: project.map { "\(service) (\($0)) stopped." } ?? "\(service) stopped."
        )
    }

    func notifyRuntimeStateChanged(running: Bool) {
        post(
            title: running ? "Runtime started" : "Runtime stopped",
            body: running ? "The container system is running." : "The container system stopped running."
        )
    }

    func notifyDiskReclaimable(_ row: DiskUsageRow) {
        post(
            title: "Disk space reclaimable",
            body: "\(row.type): \(Formatting.bytes(row.reclaimableBytes)) (\(row.reclaimablePercent)%) can be reclaimed."
        )
    }

    func notifyActionFinished(project: String, label: String, succeeded: Bool) {
        post(
            title: succeeded ? "\(project): \(label) finished" : "\(project): \(label) failed",
            body: succeeded ? "Completed successfully." : "Open the project to see what went wrong."
        )
    }

    private func post(title: String, body: String) {
        guard isAuthorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
