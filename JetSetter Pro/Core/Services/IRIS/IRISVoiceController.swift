// File: Core/Services/IRIS/IRISVoiceController.swift
//
// Runs IRIS's hands-free voice loop: listen → think → speak → listen, until
// the user stops it.
//
//   • Listening  — on-device SpeechTranscriber + SpeechAnalyzer (iOS 26+)
//                  transcribe mic audio captured via AVAudioEngine. Utterances
//                  are end-pointed with a short silence timer.
//   • Thinking   — the finalized transcript is handed to `onUtterance`, which
//                  returns IRIS's reply text.
//   • Speaking   — AVSpeechSynthesizer reads the reply. The mic is torn down
//                  while speaking so IRIS never transcribes herself (echo).
//   • Loop       — when speech finishes, listening resumes automatically.
//
// Speech (STT) types are iOS 26-only, so they're held as `Any?` and only
// touched inside `@available(iOS 26.0, *)` helpers — matching the pattern in
// IRISAgentService. AVAudioEngine / AVSpeechSynthesizer are available on the
// deployment target and used directly.
//
// REQUIRED app configuration (set in the target's Info settings):
//   • NSMicrophoneUsageDescription
//   • NSSpeechRecognitionUsageDescription
// Without these the app traps when permissions are requested.

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
final class IRISVoiceController: NSObject, ObservableObject {

    enum VoiceState: Equatable {
        case idle        // not in voice mode
        case listening   // mic open, transcribing
        case thinking    // IRIS is generating a reply
        case speaking    // IRIS is talking
    }

    @Published private(set) var state: VoiceState = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var statusMessage: String?

    /// Handles a finalized user utterance and returns IRIS's reply to speak.
    /// Return nil/empty to simply resume listening without speaking.
    var onUtterance: ((String) async -> String?)?

    /// True while the loop is active (listening / thinking / speaking).
    var isActive: Bool { state != .idle }

    // MARK: - Speech (iOS 26) — stored type-erased so this compiles below iOS 26.
    private var analyzer: Any?            // SpeechAnalyzer
    private var transcriber: Any?         // SpeechTranscriber
    private var inputBuilder: Any?        // AsyncStream<AnalyzerInput>.Continuation
    private var resultsTask: Task<Void, Never>?
    private var analyzeTask: Task<Void, Never>?

    // MARK: - Audio
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()
    private var silenceTimer: Timer?

    private let silenceCutoff: TimeInterval = 1.2

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public control

    func toggle() {
        if isActive { stop() } else { start() }
    }

    func start() {
        guard !isActive else { return }
        guard #available(iOS 26.0, *) else {
            statusMessage = "Voice requires iOS 26 on a supported device."
            return
        }
        Task { await beginSession() }
    }

    func stop() {
        teardownListening()
        synthesizer.stopSpeaking(at: .immediate)
        deactivateSession()
        liveTranscript = ""
        statusMessage = nil
        state = .idle
    }

    /// Resumes the loop from an internal restart point (listen/think/speak).
    /// Unlike `start()`, this bypasses the public `!isActive` guard, which is
    /// there to block a double-start from the UI — not internal re-listens.
    private func resumeLoop() {
        state = .idle
        start()
    }

    // MARK: - Session setup

    @available(iOS 26.0, *)
    private func beginSession() async {
        guard await requestPermissions() else {
            statusMessage = "Microphone and speech permission are needed for voice."
            state = .idle
            return
        }
        await startListening()
    }

    private func requestPermissions() async -> Bool {
        let mic = await AVAudioApplication.requestRecordPermission()
        guard mic else { return false }
        let speech = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        return speech
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Listening

    @available(iOS 26.0, *)
    private func startListening() async {
        do {
            try configureSession()

            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
                statusMessage = "Your language isn't supported for on-device transcription."
                state = .idle
                return
            }
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            self.transcriber = transcriber

            // Ensure the on-device speech assets are installed.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            self.analyzer = analyzer

            guard let audioFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                statusMessage = "Speech assets are still installing. Try again in a moment."
                state = .idle
                return
            }
            let (inputSequence, builder) = AsyncStream.makeStream(of: AnalyzerInput.self)
            self.inputBuilder = builder

            // Mic tap → resample to the analyzer's format → feed its input sequence.
            // (AVAudioConverter keeps this on iOS 26; AnalyzerInputConverter is iOS 27+.)
            let input = audioEngine.inputNode
            let tapFormat = input.outputFormat(forBus: 0)
            guard let converter = AVAudioConverter(from: tapFormat, to: audioFormat) else {
                statusMessage = "Couldn't set up the microphone audio format."
                state = .idle
                return
            }
            input.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
                guard let converted = resampleBuffer(buffer, using: converter, to: audioFormat) else { return }
                builder.yield(AnalyzerInput(buffer: converted))
            }
            audioEngine.prepare()
            try audioEngine.start()

            state = .listening
            liveTranscript = ""

            // Consume transcription results; each update restarts the silence timer.
            resultsTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await result in transcriber.results {
                        let text = String(result.text.characters)
                        await self.handleTranscriptUpdate(text)
                    }
                } catch {
                    await self.reportError("Transcription stopped.")
                }
            }

            // Drive the analyzer over the captured input.
            analyzeTask = Task { [weak self] in
                _ = try? await analyzer.analyzeSequence(inputSequence)
                _ = self
            }
        } catch {
            statusMessage = "Couldn't start listening."
            state = .idle
        }
    }

    private func handleTranscriptUpdate(_ text: String) {
        guard state == .listening else { return }
        if !text.isEmpty { liveTranscript = text }
        restartSilenceTimer()
    }

    private func restartSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceCutoff, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.endUtterance() }
        }
    }

    private func endUtterance() {
        guard state == .listening else { return }
        let text = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        teardownListening()
        guard !text.isEmpty else {
            // Nothing heard — keep listening.
            resumeLoop()
            return
        }
        liveTranscript = ""
        state = .thinking
        Task { @MainActor in
            let reply = await onUtterance?(text)
            guard isActive else { return }   // user may have stopped meanwhile
            if let reply, !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                speak(reply)
            } else {
                resumeLoop()
            }
        }
    }

    private func teardownListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        if #available(iOS 26.0, *) {
            (inputBuilder as? AsyncStream<AnalyzerInput>.Continuation)?.finish()
        }
        inputBuilder = nil
        resultsTask?.cancel(); resultsTask = nil
        analyzeTask?.cancel(); analyzeTask = nil
        analyzer = nil
        transcriber = nil
    }

    // MARK: - Speaking

    private func speak(_ text: String) {
        state = .speaking
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    private func reportError(_ message: String) {
        statusMessage = message
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension IRISVoiceController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            // Resume the loop once IRIS finishes talking.
            guard self.state == .speaking else { return }
            self.resumeLoop()
        }
    }
}

// MARK: - Audio resampling

/// Resamples a captured mic buffer into the analyzer's expected format. Runs on
/// the audio thread, so it's a free function (no actor isolation).
private func resampleBuffer(_ buffer: AVAudioPCMBuffer,
                            using converter: AVAudioConverter,
                            to format: AVAudioFormat) -> AVAudioPCMBuffer? {
    let ratio = format.sampleRate / buffer.format.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
    guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

    var supplied = false
    var conversionError: NSError?
    let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
        if supplied {
            inputStatus.pointee = .noDataNow
            return nil
        }
        supplied = true
        inputStatus.pointee = .haveData
        return buffer
    }
    guard status != .error, output.frameLength > 0 else { return nil }
    return output
}
