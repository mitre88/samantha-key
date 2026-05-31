import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let output: String
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 20,
        currentDirectory: String? = nil
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            try process.run()

            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                try await Task.sleep(nanoseconds: 50_000_000)
            }

            if process.isRunning {
                process.terminate()
                return ProcessResult(exitCode: 124, output: "Command timed out after \(Int(timeout)) seconds.")
            }

            let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let text = [output, error]
                .compactMap { String(data: $0, encoding: .utf8) }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ProcessResult(exitCode: process.terminationStatus, output: text)
        }.value
    }
}
