import Flutter
import AVFoundation

public class AudioCapturePlugin: NSObject, FlutterPlugin {

    private var audioRecorder: AVAudioRecorder?
    private var recordingPath: String?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let methodChannel = FlutterMethodChannel(
            name: "com.catinspector/audio_capture",
            binaryMessenger: registrar.messenger()
        )

        let instance = AudioCapturePlugin()
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
    }

    // MARK: - MethodChannel

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            start(result: result)
        case "stop":
            stop(result: result)
        case "isRunning":
            result(audioRecorder?.isRecording == true)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Recording

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
                self?.startRecording(result: result)
            }
        }
    }

    private func startRecording(result: FlutterResult) {
        if audioRecorder?.isRecording == true {
            result(nil)
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            result(FlutterError(
                code: "SESSION_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
            return
        }

        let dir = NSTemporaryDirectory()
        let fileName = "recording_\(Int(Date().timeIntervalSince1970 * 1000)).m4a"
        let path = (dir as NSString).appendingPathComponent(fileName)
        recordingPath = path

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]

        do {
            audioRecorder = try AVAudioRecorder(
                url: URL(fileURLWithPath: path),
                settings: settings
            )
            audioRecorder?.record()
            result(nil)
        } catch {
            result(FlutterError(
                code: "RECORDER_ERROR",
                message: error.localizedDescription,
                details: nil
            ))
        }
    }

    private func stop(result: FlutterResult) {
        guard let recorder = audioRecorder, recorder.isRecording else {
            result(nil)
            return
        }

        recorder.stop()
        audioRecorder = nil

        result(recordingPath)
        recordingPath = nil
    }
}
