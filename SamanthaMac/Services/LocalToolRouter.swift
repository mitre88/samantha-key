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
            "name": "inspect_app",
            "description": "Inspect a running app window and return its actionable accessibility tree with element indices. Use this before clicking a specific control.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Human app name, for example Safari."],
                    "bundle_id": ["type": "string", "description": "Optional bundle identifier."],
                    "window_title": ["type": "string", "description": "Optional substring of the target window title."],
                    "query": ["type": "string", "description": "Optional UI text to filter for."]
                ],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "click_text",
            "description": "Click a visible UI control in an app by matching its accessibility text. Use inspect_app first if the target label is unclear.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Visible label, title, or accessibility text to click."],
                    "name": ["type": "string", "description": "Human app name, for example Safari."],
                    "bundle_id": ["type": "string", "description": "Optional bundle identifier."],
                    "window_title": ["type": "string", "description": "Optional substring of the target window title."]
                ],
                "required": ["text"],
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
            "name": "web_search",
            "description": "Search the web in Safari or the requested browser.",
            "parameters": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query."],
                    "name": ["type": "string", "description": "Optional browser app name."],
                    "bundle_id": ["type": "string", "description": "Optional browser bundle identifier."]
                ],
                "required": ["query"],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "open_codex",
            "description": "Open Codex Desktop and optionally prepare a prompt on the clipboard for the user to paste or submit.",
            "parameters": [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string", "description": "Optional prompt to copy to the clipboard before opening Codex Desktop."]
                ],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "codex_task",
            "description": "Delegate a development, repository, analysis, or review task to Codex CLI and return its final answer. Use read_only for inspection and workspace_write only when the user explicitly asks Codex to modify files.",
            "parameters": [
                "type": "object",
                "properties": [
                    "prompt": ["type": "string", "description": "The exact task for Codex."],
                    "cwd": ["type": "string", "description": "Working directory. Defaults to the current SamanthaKey project."],
                    "mode": ["type": "string", "enum": ["read_only", "workspace_write"], "description": "read_only inspects only; workspace_write can edit files after approval."]
                ],
                "required": ["prompt"],
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
            "name": "scroll_app",
            "description": "Scroll a target app window up or down.",
            "parameters": [
                "type": "object",
                "properties": [
                    "direction": ["type": "string", "enum": ["up", "down", "left", "right"]],
                    "amount": ["type": "number", "description": "Number of page or line steps."],
                    "by": ["type": "string", "enum": ["line", "page"]],
                    "name": ["type": "string", "description": "Human app name."],
                    "bundle_id": ["type": "string", "description": "Optional bundle identifier."],
                    "window_title": ["type": "string", "description": "Optional target window title substring."]
                ],
                "required": ["direction"],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "get_clipboard",
            "description": "Read plain text from the macOS clipboard.",
            "parameters": [
                "type": "object",
                "properties": [:],
                "additionalProperties": false
            ]
        ],
        [
            "type": "function",
            "name": "set_clipboard",
            "description": "Put plain text on the macOS clipboard.",
            "parameters": [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "Text to copy to the clipboard."]
                ],
                "required": ["text"],
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
        ],
        [
            "type": "function",
            "name": "list_windows",
            "description": "List visible or known macOS windows, optionally filtered by app.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Optional app name filter."],
                    "bundle_id": ["type": "string", "description": "Optional app bundle id filter."],
                    "on_screen_only": ["type": "boolean", "description": "Whether to include only visible windows. Defaults to true."]
                ],
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
        case "codex_task":
            let mode = arguments["mode"] as? String ?? "read_only"
            if mode == "workspace_write" {
                return .needsApproval("Codex can edit files in workspace_write mode.")
            }
            return .executeNow
        case "open_app", "open_url", "show_app", "read_screen", "list_apps", "type_text", "press_key":
            return .executeNow
        case "list_windows", "inspect_app", "click_text", "scroll_app", "get_clipboard", "set_clipboard", "web_search", "open_codex":
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
            case "list_windows":
                return try await listWindows(arguments: arguments)
            case "inspect_app":
                return try await inspectApp(arguments: arguments)
            case "click_text":
                return try await clickText(arguments: arguments)
            case "scroll_app":
                return try await scrollApp(arguments: arguments)
            case "get_clipboard":
                return await getClipboard()
            case "set_clipboard":
                return await setClipboard(arguments: arguments)
            case "web_search":
                return try await webSearch(arguments: arguments)
            case "open_codex":
                return try await openCodex(arguments: arguments)
            case "codex_task":
                return try await codexTask(arguments: arguments)
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

    private func listWindows(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        var payload: [String: Any] = ["on_screen_only": arguments["on_screen_only"] as? Bool ?? true]
        if let app = try await resolveTargetApp(arguments: arguments) {
            payload["pid"] = Int(app.pid)
        }
        return try await runCUA(tool: "list_windows", payload: payload)
    }

    private func inspectApp(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let target = try await resolveTargetWindow(arguments: arguments) else {
            return ToolExecutionOutput(ok: false, text: "Could not find a matching running app window.")
        }

        var payload: [String: Any] = [
            "pid": Int(target.app.pid),
            "window_id": Int(target.windowID)
        ]
        if let query = arguments["query"] as? String, query.isEmpty == false {
            payload["query"] = query
        }
        return try await runCUAWithCaptureMode("ax", tool: "get_window_state", payload: payload)
    }

    private func clickText(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let text = arguments["text"] as? String, text.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing UI text.")
        }
        guard let target = try await resolveTargetWindow(arguments: arguments) else {
            return ToolExecutionOutput(ok: false, text: "Could not find a matching running app window.")
        }

        let inspectPayload: [String: Any] = [
            "pid": Int(target.app.pid),
            "window_id": Int(target.windowID),
            "query": text
        ]
        let snapshot = try await runCUAWithCaptureMode("ax", tool: "get_window_state", payload: inspectPayload)
        guard snapshot.ok, let elementIndex = elementIndex(matching: text, in: snapshot.text) else {
            return ToolExecutionOutput(ok: false, text: "Could not find a clickable element matching '\(text)'.")
        }

        return try await runCUA(tool: "click", payload: [
            "pid": Int(target.app.pid),
            "window_id": Int(target.windowID),
            "element_index": elementIndex
        ])
    }

    private func scrollApp(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let direction = arguments["direction"] as? String, direction.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing scroll direction.")
        }
        guard let target = try await resolveTargetWindow(arguments: arguments) else {
            return ToolExecutionOutput(ok: false, text: "Could not find a matching running app window.")
        }
        return try await runCUA(tool: "scroll", payload: [
            "pid": Int(target.app.pid),
            "window_id": Int(target.windowID),
            "direction": direction,
            "amount": arguments["amount"] as? Int ?? 3,
            "by": arguments["by"] as? String ?? "page"
        ])
    }

    private func getClipboard() async -> ToolExecutionOutput {
        let text = await MainActor.run {
            NSPasteboard.general.string(forType: .string) ?? ""
        }
        return ToolExecutionOutput(ok: true, text: text.isEmpty ? "Clipboard is empty or has no plain text." : text)
    }

    private func setClipboard(arguments: [String: Any]) async -> ToolExecutionOutput {
        guard let text = arguments["text"] as? String else {
            return ToolExecutionOutput(ok: false, text: "Missing clipboard text.")
        }
        await MainActor.run {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        return ToolExecutionOutput(ok: true, text: "Copied \(text.count) characters to the clipboard.")
    }

    private func webSearch(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let query = arguments["query"] as? String, query.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing search query.")
        }
        var searchArguments = arguments
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        searchArguments["url"] = components.url?.absoluteString ?? "https://www.google.com/search?q=\(query)"
        return try await openURL(arguments: searchArguments)
    }

    private func openCodex(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        if let prompt = arguments["prompt"] as? String, prompt.isEmpty == false {
            _ = await setClipboard(arguments: ["text": prompt])
        }
        let result = try await openApp(arguments: ["bundle_id": "com.openai.codex"])
        if let prompt = arguments["prompt"] as? String, prompt.isEmpty == false {
            return ToolExecutionOutput(ok: result.ok, text: result.text + "\nPrompt copied to clipboard for Codex Desktop.")
        }
        return result
    }

    private func codexTask(arguments: [String: Any]) async throws -> ToolExecutionOutput {
        guard let prompt = arguments["prompt"] as? String, prompt.isEmpty == false else {
            return ToolExecutionOutput(ok: false, text: "Missing Codex prompt.")
        }

        let cwd = normalizedWorkingDirectory(arguments["cwd"] as? String)
        let mode = arguments["mode"] as? String ?? "read_only"
        let sandbox = mode == "workspace_write" ? "workspace-write" : "read-only"
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("samantha-codex-\(UUID().uuidString).txt")

        let guardedPrompt = """
        You are being invoked by Samantha Mac from a voice request.
        Keep the final answer concise and directly useful.
        Do not expose secrets or API keys.

        User request:
        \(prompt)
        """

        let result = try await ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: [
                "codex", "exec",
                "--cd", cwd,
                "--sandbox", sandbox,
                "--output-last-message", outputURL.path,
                guardedPrompt
            ],
            timeout: mode == "workspace_write" ? 240 : 120
        )

        let finalMessage = (try? String(contentsOf: outputURL, encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? ""
        try? FileManager.default.removeItem(at: outputURL)

        if finalMessage.isEmpty == false {
            return ToolExecutionOutput(ok: result.exitCode == 0, text: finalMessage)
        }
        return ToolExecutionOutput(ok: result.exitCode == 0, text: result.output.isEmpty ? "Codex finished with exit \(result.exitCode)." : result.output)
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

    private func normalizedWorkingDirectory(_ rawValue: String?) -> String {
        let fallback = "/Users/dr.alexmitre/Desktop/SamanthaKey"
        guard let rawValue, rawValue.isEmpty == false else { return fallback }
        let expanded = (rawValue as NSString).expandingTildeInPath
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
            return expanded
        }
        return fallback
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

    private func runCUAWithCaptureMode(_ captureMode: String, tool: String, payload: [String: Any]) async throws -> ToolExecutionOutput {
        let previous = try await ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["cua-driver", "config", "get", "capture_mode"],
            timeout: 5
        ).output.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await ProcessRunner.run(
            executable: "/usr/bin/env",
            arguments: ["cua-driver", "config", "set", "capture_mode", captureMode],
            timeout: 5
        )
        let result = try await runCUA(tool: tool, payload: payload)
        if previous.isEmpty == false {
            _ = try await ProcessRunner.run(
                executable: "/usr/bin/env",
                arguments: ["cua-driver", "config", "set", "capture_mode", previous],
                timeout: 5
            )
        }
        return result
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

    private func resolveTargetWindow(arguments: [String: Any]) async throws -> WindowReference? {
        guard let app = try await resolveTargetApp(arguments: arguments) else { return nil }
        let result = try await runCUA(tool: "list_windows", payload: [
            "pid": Int(app.pid),
            "on_screen_only": false
        ])
        guard result.ok,
              let data = result.text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let windows = object["windows"] as? [[String: Any]] else {
            return nil
        }

        let titleQuery = (arguments["window_title"] as? String ?? "").lowercased()
        let usableWindows = windows.compactMap { window -> WindowReference? in
            guard let windowID = (window["window_id"] as? NSNumber)?.intValue else { return nil }
            let title = window["title"] as? String ?? ""
            if titleQuery.isEmpty == false, title.lowercased().contains(titleQuery) == false {
                return nil
            }
            let zIndex = (window["z_index"] as? NSNumber)?.intValue ?? 0
            let isOnScreen = window["is_on_screen"] as? Bool ?? false
            let onCurrentSpace = window["on_current_space"] as? Bool ?? false
            return WindowReference(app: app, windowID: windowID, title: title, zIndex: zIndex, isOnScreen: isOnScreen, onCurrentSpace: onCurrentSpace)
        }

        return usableWindows.sorted { lhs, rhs in
            if lhs.onCurrentSpace != rhs.onCurrentSpace { return lhs.onCurrentSpace && !rhs.onCurrentSpace }
            if lhs.isOnScreen != rhs.isOnScreen { return lhs.isOnScreen && !rhs.isOnScreen }
            return lhs.zIndex > rhs.zIndex
        }.first
    }

    private func elementIndex(matching text: String, in snapshot: String) -> Int? {
        let query = text.lowercased()
        let lines = snapshot.components(separatedBy: .newlines)
        for line in lines where line.lowercased().contains(query) {
            guard line.contains("AXButton") || line.contains("actions=[") else { continue }
            guard let start = line.firstIndex(of: "["),
                  let end = line[start...].firstIndex(of: "]") else { continue }
            let value = line[line.index(after: start)..<end]
            if let index = Int(value) { return index }
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

private struct WindowReference {
    let app: AppReference
    let windowID: Int
    let title: String
    let zIndex: Int
    let isOnScreen: Bool
    let onCurrentSpace: Bool
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
