@preconcurrency import AVFoundation
import Foundation

final class RealtimeAudioPlayer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let playbackFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!
    private let lock = NSLock()
    private var isPrepared = false

    func start() throws {
        lock.lock()
        defer { lock.unlock() }
        guard isPrepared == false else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        engine.prepare()
        try engine.start()
        player.play()
        isPrepared = true
    }

    func playPCM16(_ data: Data) {
        guard data.count >= 2 else { return }
        do { try start() } catch { return }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let channel = buffer.floatChannelData?[0] else { return }
        data.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for index in 0..<sampleCount {
                channel[index] = Float(Int16(littleEndian: samples[index])) / Float(Int16.max)
            }
        }
        player.scheduleBuffer(buffer)
        if player.isPlaying == false {
            player.play()
        }
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        if isPrepared {
            engine.detach(player)
        }
        isPrepared = false
    }
}
