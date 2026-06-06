import Foundation
import AVFoundation
import Observation
import WhisperKit

/// On-device dictation. Records the mic while you hold at the wheel's center,
/// then transcribes locally with WhisperKit and types the text into the
/// frontmost app. The model is downloaded once from `tinkerhaus/whisperkit-coreml`
/// (not bundled), so the app ships small.
///
/// Calls are made from the main thread (the wheel runs there); WhisperKit's
/// async work runs off-main and state hops back via the main queue.
@Observable
final class Voice {
    enum Status: Equatable {
        case idle, downloading(Double), preparingModel, loadingModel, ready, recording, transcribing
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
        case .preparingModel:        return "Optimizing model for your Mac…"
        case .loadingModel:          return "Loading model…"
        case .ready:                 return "Ready"
        case .recording:             return "Recording…"
        case .transcribing:          return "Transcribing…"
        case .failed(let message):   return "Error: \(message)"
        }
    }

    /// An extra line shown only during the slow first-launch prep, so it reads as
    /// expected work rather than a hang. `nil` in every other state.
    var preparingNote: String? {
        if case .preparingModel = status {
            return "First run prepares the model for your Mac's Neural Engine — this can take a few minutes. It's cached, so later launches are quick."
        }
        return nil
    }

    private let model = "openai_whisper-large-v3-v20240930_turbo"
    private let repo = "tinkerhaus/whisperkit-coreml"

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
                // Split WhisperKit's load so its slow part is legible. Building with
                // prewarm/load off makes init just locate the model (fast); we then run
                // the two phases ourselves. `prewarmModels()` is the first-launch ANE
                // "specialize" compile — minutes on a large model, and it previously hid
                // behind a single "Loading…" label that read as a hang. It's cached
                // afterwards, so later launches breeze through it.
                DispatchQueue.main.async { self?.status = .preparingModel }
                var config = WhisperKitConfig(model: model, verbose: false, logLevel: .error,
                                              prewarm: false, load: false, download: false)
                config.modelFolder = folder.path
                let pipe = try await WhisperKit(config)
                try await pipe.prewarmModels()
                DispatchQueue.main.async { self?.status = .loadingModel }
                try await pipe.loadModels()
                DispatchQueue.main.async { self?.whisper = pipe; self?.status = .ready }
            } catch {
                DispatchQueue.main.async { self?.status = .failed(error.localizedDescription) }
            }
        }
    }

    func startRecording() {
        guard isReady, recorder == nil else { return }
        pendingTranscript = nil; transcriptWaiters = []      // fresh session
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
            recorder.isMeteringEnabled = true
            recorder.record()
            smoothedLevel = 0
            self.recorder = recorder
            self.recordingURL = url
            self.status = .recording
        } catch {
            self.status = .failed(error.localizedDescription)
        }
    }

    private var smoothedLevel: Float = 0

    /// Current mic loudness, 0…1 — for the live waveform. Gated (so room tone
    /// sits near zero) and envelope-smoothed (fast attack, slow release) so it
    /// reads like a calm level meter rather than raw noise. 0 when not recording.
    func currentLevel() -> Float {
        guard let recorder, recorder.isRecording else { smoothedLevel = 0; return 0 }
        recorder.updateMeters()
        let db = recorder.averagePower(forChannel: 0)        // ~ -160 … 0 dBFS
        let floor: Float = -52
        var raw = min(1, max(0, (db - floor) / -floor))
        raw = max(0, raw - 0.05) / 0.95                      // soft noise gate
        let factor: Float = raw > smoothedLevel ? 0.45 : 0.10   // attack vs release
        smoothedLevel += (raw - smoothedLevel) * factor
        return smoothedLevel
    }

    /// Discard the in-progress recording without transcribing.
    func cancel() {
        recorder?.stop(); recorder = nil
        if let url = recordingURL { try? FileManager.default.removeItem(at: url) }
        recordingURL = nil
        pendingTranscript = nil; transcriptWaiters = []
        if status == .recording { status = .ready }
    }

    /// Stop the recorder but keep the audio — the finish-ring press means "I'm
    /// done talking"; transcription waits until a `send` commits.
    func stopRecording() {
        recorder?.stop()
        recorder = nil
        if status == .recording { status = .ready }
    }

    /// The transcript awaiting commit — `nil` until transcription finishes (then
    /// the empty string if nothing was said). Set on `transcribe`, consumed by
    /// `inject`, dropped by `cancel`/`startRecording`. Also the hinge a future
    /// voice-command runner would route instead of injecting.
    private(set) var pendingTranscript: String?
    private var transcriptWaiters: [(String) -> Void] = []

    /// Exactly what we last injected, so `undoLast()` can delete precisely that
    /// — and nothing else. Cleared once consumed or superseded.
    private(set) var lastInjected: String?

    /// Transcribe the stopped recording. Stores the result for preview, calls
    /// `onPreview` (to show it in the hub), and releases anything waiting in
    /// `send`. No-op if there's no recording.
    func transcribe(onPreview: @escaping (String) -> Void) {
        guard let url = recordingURL else { resolveTranscript(""); onPreview(""); return }
        recordingURL = nil
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
                self?.status = .ready
                self?.resolveTranscript(text)
                onPreview(text)
            }
        }
    }

    private func resolveTranscript(_ text: String) {
        pendingTranscript = text
        let waiters = transcriptWaiters
        transcriptWaiters = []
        waiters.forEach { $0(text) }
    }

    /// Call back with the transcript as soon as it's ready (immediately if it
    /// already is). Used by `send` after you commit on the finish ring.
    func whenTranscriptReady(_ completion: @escaping (String) -> Void) {
        if let pendingTranscript { completion(pendingTranscript) }
        else { transcriptWaiters.append(completion) }
    }

    /// Paste the transcript into the frontmost app and remember it for undo.
    func inject(_ text: String) {
        pendingTranscript = nil
        guard !text.isEmpty else { return }
        Keyboard.type(text)
        lastInjected = text
    }

    /// Delete the last dictation we injected — one backspace per character.
    /// App-independent (no reliance on the app's own undo), so it works in
    /// terminals and editors that ignore ⌘Z. Best-effort: do it before editing
    /// elsewhere, or it deletes from wherever the cursor now sits.
    func undoLast() {
        guard let text = lastInjected, !text.isEmpty else { return }
        for _ in 0..<text.count { Keyboard.press(Key.delete, []) }
        lastInjected = nil
    }

    /// Forget the undo buffer (a new dictation or any other action buries it).
    func clearUndo() { lastInjected = nil }
}
