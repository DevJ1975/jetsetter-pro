// File: Core/Services/Announcements/AnnouncementComposer.swift
//
// Joins a chime and recorded voice clips into one notification sound:
// linear PCM in a CAF (mono, 44.1 kHz, 16-bit), one of the formats iOS plays
// for a custom notification sound. The file goes in Library/Sounds in the app
// container, one of the places `UNNotificationSound(named:)` looks, so a
// notification can play it while the app is suspended or not running.
//
// Decisions worth knowing:
//   • Files are named by a hash of the clip list plus a format/build salt
//     (`ann_<hash>.caf`), so the same announcement is rendered once and reused,
//     and a new build with re-recorded clips never plays a stale file.
//   • iOS plays the default sound instead of any file of 30 s or more. Renders
//     stop at 29 s and fall back to the plain chime.
//   • Cleanup can't go by file age alone. A check-in reminder is often
//     scheduled days ahead, and deleting its sound before it fires would make
//     iOS play the default sound. A small ledger records when each file is last
//     needed (now, or the notification's fire date), and a file is pruned 7
//     days after that. The ledger lives in UserDefaults (already declared in
//     PrivacyInfo.xcprivacy), so no file-timestamp API is involved.
//   • Every failure (missing clip, decode error, full disk) returns nil, and
//     callers use the bundled chime. An alert always makes a sound.
//
// It's an actor so rendering and pruning never run on the main thread and two
// alerts for the same announcement can't write the same file at once.

import AVFoundation
import CryptoKit
import Foundation
import OSLog

actor AnnouncementComposer {

    nonisolated static let shared = AnnouncementComposer()
    private init() {}

    nonisolated private static let log = Logger(subsystem: "com.jetsetter.pro", category: "announcements")

    // MARK: - Tunables

    nonisolated static let sampleRate: Double = 44_100
    /// Under the 30 s limit with a margin for container overhead.
    nonisolated static let maxDuration: TimeInterval = 29
    /// How long a file is kept after the last time anything needed it.
    nonisolated static let retention: TimeInterval = 7 * 24 * 60 * 60
    /// Bump when the rendering changes (pauses, format) so old files aren't reused.
    nonisolated static let formatVersion = "v1"
    nonisolated static let filePrefix = "ann_"
    nonisolated static let ledgerKey = "announcement_sound_ledger"

    // MARK: - Naming

    /// The salt mixed into every file name: the render format plus the build
    /// number, so a build that ships re-recorded clips renders fresh files.
    nonisolated static var defaultSalt: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(formatVersion)-\(build)"
    }

    /// `ann_<16 hex>.caf`: a SHA-256 of the clip list, so the same list always
    /// maps to the same file. (`Hasher` is seeded per launch, so it can't be
    /// used for names that must survive a relaunch.)
    nonisolated static func fileName(for clips: [String], salt: String = defaultSalt) -> String {
        let input = salt + "|" + clips.joined(separator: ",")
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(filePrefix)\(hex).caf"
    }

    /// `Library/Sounds` in the app container, created when missing.
    nonisolated static func soundsDirectory() throws -> URL {
        let library = try FileManager.default.url(
            for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        return sounds
    }

    // MARK: - Public API

    /// Renders `clips` (or reuses an earlier render) and returns the file name
    /// to pass to `UNNotificationSoundName`, or nil on any failure.
    ///
    /// - Parameter neededUntil: when the notification using this sound fires.
    ///   The file is kept at least 7 days past that. Nil means now.
    func soundFileName(for clips: [String], neededUntil: Date? = nil) -> String? {
        guard !clips.isEmpty else { return nil }
        let name = Self.fileName(for: clips)
        do {
            let directory = try Self.soundsDirectory()
            let destination = directory.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try render(clips, to: destination, in: directory)
            }
            markNeeded(name, until: neededUntil)
            prune(in: directory, keeping: name)
            return name
        } catch {
            Self.log.error("Announcement render failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// The rendered file's URL, for in-app playback.
    func soundFileURL(for clips: [String]) -> URL? {
        guard let name = soundFileName(for: clips),
              let directory = try? Self.soundsDirectory() else { return nil }
        return directory.appendingPathComponent(name)
    }

    // MARK: - Rendering

    nonisolated enum ComposeError: Error {
        case formatUnavailable
        case missingClip(String)
        case bufferAllocationFailed
        case conversionFailed(String)
        case tooLong
    }

    /// Writes to a temporary `.caf` first and moves it into place, so a crash
    /// mid-render never leaves a truncated file that later gets reused.
    /// (AVAudioFile picks the container from the extension, hence `.caf`.)
    private func render(_ clips: [String], to destination: URL, in directory: URL) throws {
        let temporary = directory.appendingPathComponent("tmp-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: temporary) }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false
        ) else { throw ComposeError.formatUnavailable }

        // The file stores 16-bit integer PCM; AVAudioFile converts the float
        // buffers we write.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let output = try AVAudioFile(
            forWriting: temporary, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false
        )

        let frameLimit = AVAudioFramePosition(Self.maxDuration * Self.sampleRate)
        var framesWritten: AVAudioFramePosition = 0

        for (index, clip) in clips.enumerated() {
            let buffer = try loadClip(clip, as: format)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
            guard framesWritten <= frameLimit else { throw ComposeError.tooLong }
            try output.write(from: buffer)

            let pause = AnnouncementScript.pause(after: clip, isLast: index == clips.count - 1)
            if pause > 0 {
                let silence = try silenceBuffer(seconds: pause, format: format)
                framesWritten += AVAudioFramePosition(silence.frameLength)
                guard framesWritten <= frameLimit else { throw ComposeError.tooLong }
                try output.write(from: silence)
            }
        }
        output.close()

        try FileManager.default.moveItem(at: temporary, to: destination)
        // Alerts usually arrive with the phone locked. Pin the class that
        // stays readable after the first unlock, so a future app-wide switch
        // to `.complete` protection can't silently mute them.
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: destination.path
        )
    }

    /// Decodes one bundled clip into mono 44.1 kHz float samples. The shipped
    /// clips already are mono 44.1 kHz, so the converter only runs if a future
    /// recording arrives in another format.
    private func loadClip(_ clip: String, as format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let url = Bundle.main.url(
            forResource: clip, withExtension: AnnouncementScript.fileExtension(for: clip)
        ) else { throw ComposeError.missingClip(clip) }

        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let source = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw ComposeError.bufferAllocationFailed
        }
        try file.read(into: input)

        if source.sampleRate == format.sampleRate, source.channelCount == format.channelCount {
            return input
        }

        guard let converter = AVAudioConverter(from: source, to: format) else {
            throw ComposeError.conversionFailed(clip)
        }
        converter.downmix = true
        let ratio = format.sampleRate / source.sampleRate
        let capacity = AVAudioFrameCount((Double(input.frameLength) * ratio).rounded(.up)) + 1_024
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw ComposeError.bufferAllocationFailed
        }
        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            if delivered {
                inputStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return input
        }
        if status == .error {
            throw conversionError ?? ComposeError.conversionFailed(clip)
        }
        return converted
    }

    /// Zeroed samples. A fresh buffer's memory isn't guaranteed to be silent.
    private func silenceBuffer(seconds: TimeInterval, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount((seconds * format.sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let channels = buffer.floatChannelData else { throw ComposeError.bufferAllocationFailed }
        buffer.frameLength = frames
        for channel in 0..<Int(format.channelCount) {
            channels[channel].update(repeating: 0, count: Int(frames))
        }
        return buffer
    }

    // MARK: - Ledger and pruning

    /// File name → the latest moment anything needs it (seconds since 1970).
    private var ledger: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: Self.ledgerKey) as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: Self.ledgerKey) }
    }

    private func markNeeded(_ name: String, until date: Date?) {
        let needed = max(Date(), date ?? .distantPast).timeIntervalSince1970
        var entries = ledger
        entries[name] = max(entries[name] ?? 0, needed)
        ledger = entries
    }

    /// Deletes `ann_*.caf` files nothing has needed for `retention`, plus any
    /// temporary file a crash left behind. A file with no ledger entry (the
    /// ledger was cleared) gets one dated now rather than being deleted, in
    /// case a pending notification still uses it.
    private func prune(in directory: URL, keeping current: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        let now = Date().timeIntervalSince1970
        var entries = ledger
        for file in files {
            let url = directory.appendingPathComponent(file)
            if file.hasPrefix("tmp-"), file.hasSuffix(".caf") {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            guard file.hasPrefix(Self.filePrefix), file.hasSuffix(".caf"), file != current else { continue }
            guard let lastNeeded = entries[file] else {
                entries[file] = now
                continue
            }
            if now - lastNeeded > Self.retention {
                try? FileManager.default.removeItem(at: url)
                entries[file] = nil
            }
        }
        // Forget entries whose file is already gone.
        entries = entries.filter { files.contains($0.key) }
        ledger = entries
    }
}
