import Foundation
import AVFoundation
import Observation
import WhisperKit

/// On-device dictation. Records the mic while you hold at the wheel's center,
/// then transcribes locally with WhisperKit and types the text into the
/// frontmost app. The model is downloaded once from `haloapp/whisperkit-coreml`
/// (not bundled), so the app ships small.
///
/// Calls are made from the main thread (the wheel runs there); WhisperKit's
/// async work runs off-main and state hops back via the main queue.
@Observable
final class Voice {
    enum Status: Equatable {
        case idle, downloading(Double), loadingModel, ready, recording, transcribing
        case failed(String)
    }
    private(set) var status: Status = .idle

    /// True once the model is loaded and we can record/transcribe.
    var isReady: Bool {
        switch status { case .ready, .recording, .transcribing: return true; default: return false }
    }

    /// A short, glanceable description for the menu bar.
    var statusText: String {
        switch status {
        case .idle:                  return "Starting…"
        case .downloading(let p):    return "Downloading model… \(Int(p * 100))%"
        case .loadingModel:          return "Loading model…"
        case .ready:                 return "Ready"
        case .recording:             return "Recording…"
        case .transcribing:          return "Transcribing…"
        case .failed(let message):   return "Error: \(message)"
        }
    }

    private let model = "openai_whisper-large-v3-v20240930_turbo"
    private let repo = "haloapp/whisperkit-coreml"

    /// Called on the main thread when a dictation session finishes (text injected).
    var onFinish: (() -> Void)?

    private var whisper: WhisperKit?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?

    /// Download (with progress) then load the model in the background. Call at launch.
    func prepare() {
        guard status == .idle else { return }
        status = .downloading(0)
        AVCaptureDevice.requestAccess(for: .audio) { _ in }    // prompt mic early
        Task.detached { [model, repo, weak self] in
            do {
                let folder = try await WhisperKit.download(variant: model, from: repo) { progress in
                    DispatchQueue.main.async { self?.status = .downloading(progress.fractionCompleted) }
                }
                DispatchQueue.main.async { self?.status = .loadingModel }
                var config = WhisperKitConfig(model: model, verbose: false, logLevel: .error,
                                              prewarm: true, load: true, download: false)
                config.modelFolder = folder.path
                let pipe = try await WhisperKit(config)
                DispatchQueue.main.async { self?.whisper = pipe; self?.status = .ready }
            } catch {
                DispatchQueue.main.async { self?.status = .failed(error.localizedDescription) }
            }
        }
    }

    func startRecording() {
        guard isReady, recorder == nil else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("halo-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
            self.recordingURL = url
            self.status = .recording
        } catch {
            self.status = .failed(error.localizedDescription)
        }
    }

    /// Discard the in-progress recording without transcribing.
    func cancel() {
        recorder?.stop(); recorder = nil
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        if status == .recording { status = .ready }
    }

    /// Stop recording, transcribe, and type the result into the frontmost app.
    func stopAndInject() {
        guard let recorder, let url = recordingURL else { return }
        recorder.stop()
        self.recorder = nil
        self.recordingURL = nil
        status = .transcribing
        let whisper = whisper
        Task.detached { [weak self] in
            var options = DecodingOptions()
            options.task = .transcribe
            options.temperature = 0
            options.withoutTimestamps = true
            options.skipSpecialTokens = true
            options.suppressBlank = true

            var text = ""
            if let results = try? await whisper?.transcribe(audioPath: url.path, decodeOptions: options) {
                text = results.map(\.text).joined(separator: " ")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            try? FileManager.default.removeItem(at: url)
            DispatchQueue.main.async {
                if !text.isEmpty { Keyboard.type(text) }
                self?.status = .ready
                self?.onFinish?()
            }
        }
    }
}
