import Foundation

enum MacAgentState: Equatable {
    case idle
    case connecting
    case listening
    case acting(String)
    case needsApproval
    case error(String)

    var title: String {
        switch self {
        case .idle: "Ready"
        case .connecting: "Connecting"
        case .listening: "Listening"
        case .acting(let tool): "Running \(tool)"
        case .needsApproval: "Approval needed"
        case .error: "Needs attention"
        }
    }
}

struct AgentLogEntry: Identifiable, Equatable {
    enum Kind: String {
        case info
        case user
        case assistant
        case tool
        case error
    }

    let id = UUID()
    let date = Date()
    let kind: Kind
    let message: String
}

struct ToolApprovalRequest: Identifiable, Equatable {
    let id = UUID()
    let callID: String
    let name: String
    let arguments: [String: AnySendable]
    let reason: String

    var summary: String {
        let args = arguments.map { "\($0.key): \($0.value.value)" }.joined(separator: "\n")
        return args.isEmpty ? reason : "\(reason)\n\n\(args)"
    }

    static func == (lhs: ToolApprovalRequest, rhs: ToolApprovalRequest) -> Bool {
        lhs.id == rhs.id
    }
}

struct AnySendable: @unchecked Sendable, Equatable, CustomStringConvertible {
    let value: Any

    var description: String {
        if let string = value as? String { return string }
        return String(describing: value)
    }

    static func == (lhs: AnySendable, rhs: AnySendable) -> Bool {
        lhs.description == rhs.description
    }
}

struct PendingFunctionCall: Sendable {
    let callID: String
    let name: String
    let argumentsJSON: String
}
