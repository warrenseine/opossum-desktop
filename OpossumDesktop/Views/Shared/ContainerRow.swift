import SwiftUI
import OpossumKit

struct ContainerRow: View {
    let container: ContainerInfo

    var body: some View {
        HStack {
            StatusDot(kind: .init(containerState: container.status.state))
            VStack(alignment: .leading, spacing: 2) {
                Text(container.serviceName).font(.body.weight(.medium))
                Text(container.configuration.image.reference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let port = container.configuration.publishedPorts?.first?.hostPort {
                Text(":\(port)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text(container.isRunning ? Formatting.duration(since: container.status.startedDate) : container.status.state)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}
