import AppKit
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
            "description": "Launch a macOS app and bring it forward for the user.",
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
            "name": "open_url",
            "description": "Open a URL in a browser and bring that browser forward.",
            "parameters": [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "The full URL to open."],
                    "name": ["type": "string", "description": "Optional browser app name, for example Safari or Google Chrome."],
                    "bundle_id": ["type": "string", "description": "Optional browser bundle identifier."]
                ],
                "required": ["url"],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "show_app",
            "description": "Bring a running or launchable app forward for the user.",
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
            "name": "type_text",
            "description": "Type text into the focused field of a target app.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to type."],
                    "name": ["type": "string", "description": "Target app name."],
                    "bundle_id": ["type": "string", "description": "Optional target app bundle identifier."]
                ],
                "required": ["text"],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "press_key",
            "description": "Press a key or shortcut in a target app.",
            "parameters": [
                "type": "object",
                "properties": [
                    "key": ["type": "string", "description": "Key name, for example return, tab, escape, a, 1."],
                    "modifiers": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Optional modifiers: cmd, shift, option, ctrl, fn."
                    ],
                    "name": ["type": "string", "description": "Target app name."],
                    "bundle_id": ["type": "string", "description": "Optional target app bundle identifier."]
                ],
                "required": ["key"],
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
        case "open_app", "open_url", "show_app", "read_screen", "list_apps", "type_text", "press_key":
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
            case "open_url":
                return try await openURL(arguments: arguments)
            case "show_app":
                return try await showApp(arguments: arguments)
            case "read_screen":
                return try await readScreen(arguments: arguments)
            case "list_apps":
                return try await runCUA(tool: "list_apps", payload: [:])
            case "type_text":
                return try await typeText(arguments: arguments)
            case "press_key":
                return try await pressKey(arguments: arguments)
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
        let result = try await runCUA(tool: "launch_app", payload: payload)
        if result.ok {
            await bringLaunchedAppForward(from: result.text, fallbackBundleID: payload["bundle_id"] as? String)
        }
        return result
    }

    private func openURL(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let url = arguments["url"] as? String, url.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing URL.")
        }

        var payload: [String: Any] = ["urls": [url]]
        if let bundleID = arguments["bundle_id"] as? String, bundleID.isEmpty == false {
            payload["bundle_id"] = bundleID
        } else if let name = arguments["name"] as? String, name.isEmpty == false {
            payload["name"] = name
        } else {
            payload["bundle_id"] = "com.apple.Safari"
        }

        let result = try await runCUA(tool: "launch_app", payload: payload)
        if result.ok {
            await bringLaunchedAppForward(from: result.text, fallbackBundleID: payload["bundle_id"] as? String)
        }
        return result
    }

    private func showApp(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        try await openApp(arguments: arguments)
    }

    private func readScreen(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        let mode = arguments["mode"] as? String ?? "accessibility_tree"
        if mode == "windows" {
            return try await runCUA(tool: "list_windows", payload: ["on_screen_only": true])
        }
        return try await runCUA(tool: "get_accessibility_tree", payload: [:])
    }

    private func typeText(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let text = arguments["text"] as? String, text.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing text.")
        }
        guard let app = try await resolveTargetApp(arguments: arguments) else {
            return ToolExecutionOutput(ok: false, text: "Target app is not running. Open or show the app first.")
        }

        await bringRunningAppForward(pid: app.pid, bundleID: app.bundleID)
        return try await runCUA(tool: "type_text_chars", payload: [
            "pid": Int(app.pid),
            "text": text,
            "delay_ms": 15
        ])
    }

    private func pressKey(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let key = arguments["key"] as? String, key.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing key.")
        }
        guard let app = try await resolveTargetApp(arguments: arguments) else {
            return ToolExecutionOutput(ok: false, text: "Target app is not running. Open or show the app first.")
        }

        await bringRunningAppForward(pid: app.pid, bundleID: app.bundleID)
        let modifiers = arguments["modifiers"] as? [String] ?? []
        if modifiers.isEmpty {
            return try await runCUA(tool: "press_key", payload: [
                "pid": Int(app.pid),
                "key": key
            ])
        }

        return try await runCUA(tool: "hotkey", payload: [
            "pid": Int(app.pid),
            "keys": modifiers + [key]
        ])
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

    private func bringLaunchedAppForward(from output: String, fallbackBundleID: String?) async {
        let appReference = parseLaunchedAppReference(from: output, fallbackBundleID: fallbackBundleID)
        await bringRunningAppForward(pid: appReference.pid, bundleID: appReference.bundleID)
    }

    private func bringRunningAppForward(pid: pid_t?, bundleID: String?) async {
        await MainActor.run {
            let app: NSRunningApplication?
            if let pid {
                app = NSRunningApplication(processIdentifier: pid)
            } else if let bundleID {
                app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            } else {
                app = nil
            }

            guard let app else { return }
            app.unhide()
            app.activate(options: [.activateAllWindows])
        }
    }

    private func parseLaunchedAppReference(from output: String, fallbackBundleID: String?) -> (pid: pid_t?, bundleID: String?) {
        guard let data = output.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, fallbackBundleID)
        }
        let pid = (object["pid"] as? NSNumber)?.int32Value
        let bundleID = object["bundle_id"] as? String
        return (pid, bundleID ?? fallbackBundleID)
    }

    private func resolveTargetApp(arguments: [String: Any]) async throws -> AppReference? {
        if let bundleID = arguments["bundle_id"] as? String, bundleID.isEmpty == false,
           let app = await runningApp(bundleID: bundleID) {
            return app
        }

        guard let name = arguments["name"] as? String, name.isEmpty == false else {
            return nil
        }

        let result = try await runCUA(tool: "list_apps", payload: [:])
        guard result.ok,
              let data = result.text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let apps = object["apps"] as? [[String: Any]] else {
            return nil
        }

        let query = name.lowercased()
        for app in apps {
            let appName = (app["name"] as? String ?? "").lowercased()
            let bundleID = (app["bundle_id"] as? String ?? "").lowercased()
            guard appName == query || appName.contains(query) || bundleID.contains(query) else { continue }
            guard let running = app["running"] as? Bool, running,
                  let pidNumber = app["pid"] as? NSNumber else { return nil }
            return AppReference(pid: pidNumber.int32Value, bundleID: app["bundle_id"] as? String)
        }
        return nil
    }

    @MainActor
    private func runningApp(bundleID: String) -> AppReference? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        return AppReference(pid: app.processIdentifier, bundleID: bundleID)
    }
}

private struct AppReference {
    let pid: pid_t
    let bundleID: String?
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
