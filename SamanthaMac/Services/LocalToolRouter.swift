import Foundation

enum ToolAssessment: Sendable {
    case executeNow
    case needsApproval(String)
}

struct ToolExecutionOutput: Sendable {
    let ok: Bool
    let text: String

    var jsonString: String {
        let object: [String: Any] = ["ok": ok, "output": text]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: data, encoding: .utf8) else {
            return #"{"ok":false,"output":"Could not serialize tool output."}"#
        }
        return string
    }
}

struct LocalToolRouter: Sendable {
    nonisolated(unsafe) static let toolSchemas: [[String: Any]] = [
        [
            "type": "function",
            "name": "shell_exec",
            "description": "Run a local shell command on this Mac. Read-only commands may run directly; mutating or dangerous commands require user approval.",
            "parameters": [
                "type": "object",
                "properties": [
                    "command": ["type": "string", "description": "The shell command to run."],
                    "cwd": ["type": "string", "description": "Optional working directory."]
                ],
                "required": ["command"],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "open_app",
            "description": "Launch a macOS app without intentionally stealing focus by using cua-driver launch_app.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Human app name, for example Safari."],
                    "bundle_id": ["type": "string", "description": "Optional bundle identifier."]
                ],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "read_screen",
            "description": "Read the current macOS accessibility tree only when needed to understand visible apps/windows.",
            "parameters": [
                "type": "object",
                "properties": [
                    "mode": [
                        "type": "string",
                        "enum": ["accessibility_tree", "windows"],
                        "description": "Use accessibility_tree for visible UI text, windows for window list."
                    ]
                ],
                "required": ["mode"],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "list_apps",
            "description": "List running and installed regular macOS apps through cua-driver.",
            "parameters": [
                "type": "object",
                "properties": [:],
                "additionalProperties": false
            ]
        ]
    ]

    func assess(name: String, arguments: [String: Any]) -> ToolAssessment {
        switch name {
        case "shell_exec":
            let command = arguments["command"] as? String ?? ""
            switch ShellCommandPolicy.assess(command) {
            case .allowed: return .executeNow
            case .approvalRequired(let reason): return .needsApproval(reason)
            }
        case "open_app", "read_screen", "list_apps":
            return .executeNow
        default:
            return .needsApproval("Unknown tools are blocked until the user approves them.")
        }
    }

    func execute(name: String, arguments: [String: Any]) async -> ToolExecutionOutput {
        do {
            switch name {
            case "shell_exec":
                return try await runShell(arguments: arguments)
            case "open_app":
                return try await openApp(arguments: arguments)
            case "read_screen":
                return try await readScreen(arguments: arguments)
            case "list_apps":
                return try await runCUA(tool: "list_apps", payload: [:])
            default:
                return ToolExecutionOutput(ok: false, text: "Unknown tool: \(name)")
            }
        } catch {
            return ToolExecutionOutput(ok: false, text: error.localizedDescription)
        }
    }

    private func runShell(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let command = arguments["command"] as? String, command.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing command.")
        }
        let cwd = arguments["cwd"] as? String
        let result = try await ProcessRunner.run(
            executable: "/bin/zsh",
            arguments: ["-lc", command],
            timeout: 30,
            currentDirectory: cwd
        )
        return ToolExecutionOutput(ok: result.exitCode == 0, text: result.output.isEmpty ? "Exit \(result.exitCode)" : result.output)
    }

    private func openApp(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        var payload: [String: Any] = [:]
        if let bundleID = arguments["bundle_id"] as? String, bundleID.isEmpty == false {
            payload["bundle_id"] = bundleID
        }
        if let name = arguments["name"] as? String, name.isEmpty == false {
            payload["name"] = name
        }
        guard payload.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing app name or bundle_id.")
        }
        return try await runCUA(tool: "launch_app", payload: payload)
    }

    private func readScreen(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        let mode = arguments["mode"] as? String ?? "accessibility_tree"
        if mode == "windows" {
            return try await runCUA(tool: "list_windows", payload: ["on_screen_only": true])
        }
        return try await runCUA(tool: "get_accessibility_tree", payload: [:])
    }

    private func runCUA(tool: String, payload: [String: Any]) async throws -> ToolExecutionOutput {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let result = try await ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["cua-driver", tool, json],
            timeout: 20
        )
        return ToolExecutionOutput(ok: result.exitCode == 0, text: result.output.isEmpty ? "Exit \(result.exitCode)" : result.output)
    }
}

enum ToolJSON {
    static func decodeArguments(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return object
    }

    static func sendableArguments(_ arguments: [String: Any]) -> [String: AnySendable] {
        arguments.reduce(into: [:]) { result, entry in
            result[entry.key] = AnySendable(value: entry.value)
        }
    }
}
