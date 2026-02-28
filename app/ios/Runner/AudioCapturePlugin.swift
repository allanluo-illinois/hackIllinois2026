import Flutter
import AVFoundation

public class AudioCapturePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {

    private let audioEngine = AVAudioEngine()
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()

        let methodChannel = FlutterMethodChannel(
            name: "com.catinspector/audio_capture",
            binaryMessenger: messenger
        )
        let eventChannel = FlutterEventChannel(
            name: "com.catinspector/audio_stream",
            binaryMessenger: messenger
        )

        let instance = AudioCapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            start(result: result)
        case "stop":
            stop(result: result)
        case "isRunning":
            result(audioEngine.isRunning)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil
        return nil
    }

    // MARK: - Lifecycle

    private func start(result: @escaping FlutterResult) {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    result(FlutterError(
                        code: "PERMISSION_DENIED",
                        message: "Microphone permission denied",
                        details: nil
                    ))
                    return
                }
                self?.startEngine(result: result)
            }
        }
    }

    private func startEngine(result: FlutterResult) {
        guard !audioEngine.isRunning else {
            result(nil)
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            result(FlutterError(code: "SESSION_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        let inputNode = audioEngine.inputNode
        let nativeFormat = inputNode.outputFormat(forBus: 0)

        let pcm16Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: nativeFormat.sampleRate,
            channels: 1,
            interleaved: true
        )!

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, _ in
            guard let self = self, let sink = self.eventSink else { return }

            let rmsDb = Self.rmsDecibels(buffer: buffer)

            guard let converted = self.convertToPCM16(buffer: buffer, outputFormat: pcm16Format) else { return }

            let pcmData = Data(
                bytes: converted.int16ChannelData!.pointee,
                count: Int(converted.frameLength) * MemoryLayout<Int16>.size
            )

            DispatchQueue.main.async {
                sink([
                    "pcm": FlutterStandardTypedData(bytes: pcmData),
                    "rmsDb": rmsDb,
                ] as [String: Any])
            }
        }

        do {
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            result(FlutterError(code: "ENGINE_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        result(nil)
    }

    private func stop(result: FlutterResult) {
        guard audioEngine.isRunning else {
            result(nil)
            return
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            result(FlutterError(code: "SESSION_ERROR", message: error.localizedDescription, details: nil))
            return
        }

        result(nil)
    }

    // MARK: - Level Metering

    private static func rmsDecibels(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return -160.0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return -160.0 }

        let samples = channelData.pointee
        var sum: Float = 0.0
        for i in 0..<frames {
            let s = samples[i]
            sum += s * s
        }
        let rms = sqrtf(sum / Float(frames))
        return rms > 0 ? 20.0 * log10f(rms) : -160.0
    }

    // MARK: - PCM Conversion

    private func convertToPCM16(buffer: AVAudioPCMBuffer, outputFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: outputFormat) else { return nil }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        return error == nil ? outputBuffer : nil
    }
}
