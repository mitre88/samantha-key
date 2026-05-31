@preconcurrency import AVFoundation
import Foundation

final class MicrophoneStreamer: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 24_000,
        channels: 1,
        interleaved: true
    )!
    private var converter: AVAudioConverter?

    func start(onChunk: @escaping @Sendable (Data) -> Void) throws {
        stop()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        inputNode.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let data = self.convert(buffer), data.isEmpty == false else { return }
            onChunk(data)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        if engine.inputNode.numberOfInputs > 0 {
            engine.inputNode.removeTap(onBus: 0)
        }
        if engine.isRunning {
            engine.stop()
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let frameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else { return nil }

        let inputState = ConverterInputState()
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if inputState.didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputState.didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, conversionError == nil else { return nil }
        let byteCount = Int(outputBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        guard byteCount > 0,
              let dataPointer = outputBuffer.audioBufferList.pointee.mBuffers.mData else { return nil }
        return Data(bytes: dataPointer, count: byteCount)
    }
}

private final class ConverterInputState: @unchecked Sendable {
    var didProvideInput = false
}
