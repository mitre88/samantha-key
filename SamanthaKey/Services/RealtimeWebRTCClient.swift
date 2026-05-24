import AVFoundation
import Foundation
@preconcurrency import WebRTC

final class RealtimeWebRTCClient: NSObject, @unchecked Sendable {
    private static let initializeWebRTC: Void = {
        RTCInitializeSSL()
        let configuration = RTCAudioSessionConfiguration.webRTC()
        configuration.category = AVAudioSession.Category.playAndRecord.rawValue
        configuration.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
        configuration.sampleRate = 48_000
        configuration.ioBufferDuration = 0.02
        configuration.inputNumberOfChannels = 1
        configuration.outputNumberOfChannels = 1
        RTCAudioSessionConfiguration.setWebRTC(configuration)
    }()

    private let stateLock = NSLock()
    private var _peerConnectionFactory: RTCPeerConnectionFactory?
    private var _peerConnection: RTCPeerConnection?
    private var _dataChannel: RTCDataChannel?
    private var _pendingSessionUpdate: [String: Any]?
    private var _onEvent: (@MainActor @Sendable (String) -> Void)?
    private var _onFailure: (@MainActor @Sendable (String) -> Void)?
    private var _isDisconnecting = false

    deinit {
        disconnect()
    }

    func connect(
        token: String,
        endpoint: URL,
        outputLanguage: AppLanguage,
        onEvent: @escaping @MainActor @Sendable (String) -> Void,
        onFailure: @escaping @MainActor @Sendable (String) -> Void
    ) async throws {
        Self.initializeWebRTC
        stateLock.withLock {
            _isDisconnecting = false
            _onEvent = onEvent
            _onFailure = onFailure
        }

        try configureAudioSession()

        let factory = RTCPeerConnectionFactory()
        stateLock.withLock { _peerConnectionFactory = factory }

        let configuration = RTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = [
            RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])
        ]

        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: self) else {
            throw RealtimeWebRTCError.peerConnectionUnavailable
        }
        stateLock.withLock { _peerConnection = peerConnection }

        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: [
                "googEchoCancellation": "true",
                "googAutoGainControl": "true",
                "googNoiseSuppression": "true",
                "googHighpassFilter": "true"
            ]
        )
        let audioSource = factory.audioSource(with: audioConstraints)
        let audioTrack = factory.audioTrack(with: audioSource, trackId: "samantha-microphone")
        let audioTransceiverInit = RTCRtpTransceiverInit()
        audioTransceiverInit.direction = RTCRtpTransceiverDirection.sendRecv
        audioTransceiverInit.streamIds = ["samantha-key"]
        guard peerConnection.addTransceiver(with: audioTrack, init: audioTransceiverInit) != nil else {
            throw RealtimeWebRTCError.audioTransceiverUnavailable
        }

        let channelConfig = RTCDataChannelConfiguration()
        guard let dataChannel = peerConnection.dataChannel(forLabel: "oai-events", configuration: channelConfig) else {
            throw RealtimeWebRTCError.dataChannelUnavailable
        }
        dataChannel.delegate = self
        stateLock.withLock {
            _dataChannel = dataChannel
            _pendingSessionUpdate = Self.sessionUpdatePayload(outputLanguage: outputLanguage)
        }

        let offerSDP = try await peerConnection.createAndSetLocalOffer(with: constraints)
        let answerSDP = try await Self.fetchRemoteAnswer(endpoint: endpoint, token: token, localSDP: offerSDP)
        try await peerConnection.setRemoteAnswerSDP(answerSDP)
    }

    func updateOutputLanguage(_ outputLanguage: AppLanguage) throws {
        let payload = Self.sessionUpdatePayload(outputLanguage: outputLanguage)
        let channel = stateLock.withLock { _dataChannel }
        if channel?.readyState == .open {
            try sendJSON(payload)
        } else {
            stateLock.withLock { _pendingSessionUpdate = payload }
        }
    }

    func disconnect() {
        let (activeDataChannel, activePeerConnection) = stateLock.withLock {
            _isDisconnecting = true
            _onEvent = nil
            _onFailure = nil
            _pendingSessionUpdate = nil

            let dc = _dataChannel
            let pc = _peerConnection

            _dataChannel = nil
            _peerConnection = nil
            _peerConnectionFactory = nil

            return (dc, pc)
        }

        activeDataChannel?.delegate = nil
        activeDataChannel?.close()
        activePeerConnection?.close()

        deactivateAudioSession()
    }

    private func configureAudioSession() throws {
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = true
        session.isAudioEnabled = true
        session.ignoresPreferredAttributeConfigurationErrors = true
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }

        try session.setCategory(
            AVAudioSession.Category.playAndRecord,
            mode: AVAudioSession.Mode.voiceChat,
            options: [.defaultToSpeaker, .allowBluetoothHFP]
        )
        try session.setPreferredSampleRate(48_000)
        try session.setPreferredIOBufferDuration(0.02)
        try session.overrideOutputAudioPort(.speaker)
        try session.setActive(true)
    }

    private func deactivateAudioSession() {
        let session = RTCAudioSession.sharedInstance()
        session.isAudioEnabled = false
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.setActive(false)
    }

    private func flushPendingSessionUpdateIfNeeded() {
        let (disconnecting, channel, pending, failureHandler) = stateLock.withLock {
            (_isDisconnecting, _dataChannel, _pendingSessionUpdate, _onFailure)
        }
        guard !disconnecting, channel?.readyState == .open, let pending else { return }
        do {
            try sendJSON(pending)
            stateLock.withLock { _pendingSessionUpdate = nil }
        } catch {
            Task { @MainActor in failureHandler?(error.localizedDescription) }
        }
    }

    private func sendJSON(_ object: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: object)
        let channel = stateLock.withLock { _dataChannel }
        guard let channel else { throw RealtimeWebRTCError.dataChannelUnavailable }
        channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    private static func fetchRemoteAnswer(endpoint: URL, token: String, localSDP: String) async throws -> String {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.setValue("application/sdp", forHTTPHeaderField: "Accept")
        request.httpBody = localSDP.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw RealtimeWebRTCError.signalingFailed(body)
        }
        guard let answer = String(data: data, encoding: .utf8), !answer.isEmpty else {
            throw RealtimeWebRTCError.emptySDPAnswer
        }
        return answer
    }

    private static func sessionUpdatePayload(outputLanguage: AppLanguage) -> [String: Any] {
        [
            "type": "session.update",
            "session": [
                "audio": [
                    "output": [
                        "language": outputLanguage.realtimeTranslationCode
                    ]
                ]
            ]
        ]
    }
}

extension RealtimeWebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if rtpReceiver.track?.kind == kRTCMediaStreamTrackKindAudio {
            ensureAudioPlayoutEnabled()
            rtpReceiver.track?.isEnabled = true
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if stream.audioTracks.isEmpty == false {
            ensureAudioPlayoutEnabled()
            stream.audioTracks.forEach { $0.isEnabled = true }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        let (disconnecting, failureHandler) = stateLock.withLock { (_isDisconnecting, _onFailure) }
        guard !disconnecting else { return }
        if newState == .connected || newState == .completed {
            ensureAudioPlayoutEnabled()
        } else if newState == .failed || newState == .disconnected || newState == .closed {
            Task { @MainActor in failureHandler?("The realtime audio connection closed.") }
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        guard !stateLock.withLock({ _isDisconnecting }) else { return }
        dataChannel.delegate = self
        stateLock.withLock { _dataChannel = dataChannel }
        flushPendingSessionUpdateIfNeeded()
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if transceiver.mediaType == RTCRtpMediaType.audio {
            ensureAudioPlayoutEnabled()
        }
    }

    private func ensureAudioPlayoutEnabled() {
        let session = RTCAudioSession.sharedInstance()
        session.isAudioEnabled = true
        session.lockForConfiguration()
        defer { session.unlockForConfiguration() }
        try? session.overrideOutputAudioPort(.speaker)
    }
}

extension RealtimeWebRTCClient: RTCDataChannelDelegate {
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        let (disconnecting, failureHandler) = stateLock.withLock { (_isDisconnecting, _onFailure) }
        guard !disconnecting else { return }
        if dataChannel.readyState == .open {
            flushPendingSessionUpdateIfNeeded()
        } else if dataChannel.readyState == .closed {
            Task { @MainActor in failureHandler?("The realtime event channel closed.") }
        }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let (disconnecting, eventHandler) = stateLock.withLock { (_isDisconnecting, _onEvent) }
        guard !disconnecting else { return }
        guard !buffer.isBinary,
              let text = String(data: buffer.data, encoding: .utf8) else { return }
        Task { @MainActor in eventHandler?(text) }
    }
}

private extension RTCPeerConnection {
    func createAndSetLocalOffer(with constraints: RTCMediaConstraints) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            offer(for: constraints) { description, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let description {
                    let sdp = description.sdp
                    self.setLocalDescription(description) { error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: sdp)
                        }
                    }
                } else {
                    continuation.resume(throwing: RealtimeWebRTCError.offerFailed)
                }
            }
        }
    }

    func setRemoteAnswerSDP(_ sdp: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let description = RTCSessionDescription(type: .answer, sdp: sdp)
            setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

private enum RealtimeWebRTCError: LocalizedError {
    case peerConnectionUnavailable
    case dataChannelUnavailable
    case audioTransceiverUnavailable
    case offerFailed
    case emptySDPAnswer
    case signalingFailed(String)

    var errorDescription: String? {
        switch self {
        case .peerConnectionUnavailable:
            "The realtime audio connection could not be created."
        case .dataChannelUnavailable:
            "The realtime event channel could not be created."
        case .audioTransceiverUnavailable:
            "The realtime audio output could not be negotiated."
        case .offerFailed:
            "The realtime audio offer could not be created."
        case .emptySDPAnswer:
            "The realtime service returned an empty audio answer."
        case .signalingFailed(let message):
            "Realtime call failed: \(message)"
        }
    }
}
