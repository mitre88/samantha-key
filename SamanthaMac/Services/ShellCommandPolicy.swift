import Foundation

enum CommandRisk: Sendable {
    case allowed
    case approvalRequired(String)
}

enum ShellCommandPolicy {
    private static let readOnlyPrefixes = [
        "pwd", "ls", "date", "whoami", "id", "uname", "sw_vers",
        "git status", "git diff", "git log", "rg ", "find ", "cat ", "sed -n",
        "head ", "tail ", "wc ", "du ", "df ", "which "
    ]

    private static let dangerousPatterns = [
        #"(^|\s)rm\s"#,
        #"(^|\s)sudo\s"#,
        #"(^|\s)kill(all)?\s"#,
        #"(^|\s)pkill\s"#,
        #"(^|\s)mv\s"#,
        #"(^|\s)cp\s"#,
        #"(^|\s)chmod\s"#,
        #"(^|\s)chown\s"#,
        #"(^|\s)curl\s.*\|\s*(sh|bash|zsh)"#,
        #">\s*/"#,
        #"\|\s*(sh|bash|zsh)"#
    ]

    static func assess(_ command: String) -> CommandRisk {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return .approvalRequired("Empty shell commands are not run.")
        }

        if readOnlyPrefixes.contains(where: { trimmed == $0.trimmingCharacters(in: .whitespaces) || trimmed.hasPrefix($0) }) {
            return .allowed
        }

        for pattern in dangerousPatterns where trimmed.range(of: pattern, options: .regularExpression) != nil {
            return .approvalRequired("This shell command can change local state or affect another process.")
        }

        return .approvalRequired("Shell commands outside the read-only allowlist need approval.")
    }
}
