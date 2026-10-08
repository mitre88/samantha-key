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
    private var scheduledUntil = Date.distantPast

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

    @discardableResult
    func playPCM16(_ data: Data) -> Date? {
        guard data.count >= 2 else { return nil }
        do { try start() } catch { return nil }

        let sampleCount = data.count / MemoryLayout<Int16>.size
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(sampleCount)
        ) else { return nil }
        buffer.frameLength = AVAudioFrameCount(sampleCount)

        guard let channel = buffer.floatChannelData?[0] else { return nil }
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

        lock.lock()
        let start = max(Date(), scheduledUntil)
        scheduledUntil = start.addingTimeInterval(TimeInterval(sampleCount) / playbackFormat.sampleRate)
        let end = scheduledUntil
        lock.unlock()
        return end
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        player.stop()
        scheduledUntil = .distantPast
        if engine.isRunning {
            engine.stop()
        }
        if isPrepared {
            engine.detach(player)
        }
        isPrepared = false
    }
}
