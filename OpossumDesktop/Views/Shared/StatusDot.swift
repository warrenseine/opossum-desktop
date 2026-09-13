import SwiftUI

struct StatusDot: View {
    enum Kind { case running, stopped, warning, unknown }
    let kind: Kind

    private var color: Color {
        switch kind {
        case .running: .green
        case .stopped: .secondary
        case .warning: .orange
        case .unknown: .gray
        }
    }

    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

extension StatusDot.Kind {
    init(containerState: String) {
        switch containerState.lowercased() {
        case "running": self = .running
        case "stopped", "exited", "created": self = .stopped
        default: self = .unknown
        }
    }
}
