import Foundation

public enum TerminalApp: String, Sendable, CaseIterable, Codable {
    case terminal = "Terminal"
    case iterm = "iTerm"
}

/// Opens `opossum exec -it <service> <shell>` in the user's terminal of choice, rather than an
/// embedded terminal emulator — this is the whole implementation of the Exec feature.
public enum TerminalLauncher {
    public static func exec(
        project: ProjectContext,
        service: String,
        shell: String = "sh",
        app: TerminalApp = .terminal,
        opossumBinary: String
    ) throws {
        var args = ["exec", "-it"] + project.globalFlags + [service, shell]
        args = args.map(shellQuote)
        let command = "cd \(shellQuote(project.directory.path)) && \(shellQuote(opossumBinary)) " + args.joined(separator: " ")

        let script: String
        switch app {
        case .terminal:
            script = """
            tell application "Terminal"
                activate
                do script "\(escapeForAppleScript(command))"
            end tell
            """
        case .iterm:
            script = """
            tell application "iTerm"
                activate
                create window with default profile
                tell current session of current window
                    write text "\(escapeForAppleScript(command))"
                end tell
            end tell
            """
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try process.run()
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escapeForAppleScript(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
