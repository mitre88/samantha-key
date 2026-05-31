import SwiftUI

struct MacAssistantView: View {
    @Bindable var agent: MacVoiceAgent
    @State private var apiKeyDraft = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), .cyan.opacity(0.08), .black.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 22) {
                header
                orb
                transcriptPanel
                approvalPanel
                controls
                settings
            }
            .padding(28)
        }
        .onAppear {
            apiKeyDraft = agent.maskedAPIKey
            agent.installHotkeyMonitor()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Samantha Mac")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                Text("Voice in. Local action out.")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var statusPill: some View {
        Text(agent.state.title)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: Capsule())
    }

    private var orb: some View {
        Button {
            Task { await agent.toggleListening() }
        } label: {
            ZStack {
                Circle()
                    .fill(.white)
                    .shadow(color: .cyan.opacity(agent.isRunning ? 0.42 : 0.18), radius: agent.isRunning ? 42 : 18)
                Circle()
                    .stroke(.black.opacity(0.12), lineWidth: 2)
                    .padding(18)
                Image(systemName: agent.isRunning ? "waveform" : "mic.fill")
                    .font(.system(size: 52, weight: .bold))
                    .foregroundStyle(.black)
                    .symbolEffect(.pulse, options: .repeating, isActive: agent.isRunning)
            }
            .frame(width: 176, height: 176)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(agent.isRunning ? "Stop listening" : "Start listening")
    }

    private var transcriptPanel: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if agent.userDraft.isEmpty == false {
                        DraftBubble(title: "USER", text: agent.userDraft, color: .blue)
                    }
                    if agent.assistantDraft.isEmpty == false {
                        DraftBubble(title: "SAMANTHA", text: agent.assistantDraft, color: .green)
                    }
                    ForEach(agent.logs.suffix(80)) { entry in
                        LogBubble(entry: entry)
                            .id(entry.id)
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 180, maxHeight: 260)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(.white.opacity(0.35), lineWidth: 1)
            )
            .onChange(of: agent.logs.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var approvalPanel: some View {
        if let request = agent.pendingApproval {
            VStack(alignment: .leading, spacing: 12) {
                Label("Confirm local action", systemImage: "exclamationmark.shield.fill")
                    .font(.headline)
                Text(request.summary)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                HStack {
                    Button("Deny") {
                        Task { await agent.rejectPendingTool() }
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Approve") {
                        Task { await agent.approvePendingTool() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.black)
                }
            }
            .padding(16)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                Task { await agent.toggleListening() }
            } label: {
                Label(agent.isRunning ? "Stop" : "Start", systemImage: agent.isRunning ? "stop.fill" : "mic.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.black)

            Button {
                agent.clearLogs()
            } label: {
                Image(systemName: "trash")
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(.bordered)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OpenAI API key")
                .font(.headline)
            SecureField("sk-...", text: $apiKeyDraft)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("Use `gpt-realtime-2`. API keys stay in local Keychain and are not committed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save") {
                    agent.saveAPIKey(apiKeyDraft)
                    apiKeyDraft = agent.maskedAPIKey
                }
            }
        }
    }
}

private struct DraftBubble: View {
    let title: String
    let text: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text(text)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct LogBubble: View {
    let entry: AgentLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.kind.rawValue.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(color)
            Text(entry.message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var color: Color {
        switch entry.kind {
        case .info: .secondary
        case .user: .blue
        case .assistant: .green
        case .tool: .purple
        case .error: .red
        }
    }
}
