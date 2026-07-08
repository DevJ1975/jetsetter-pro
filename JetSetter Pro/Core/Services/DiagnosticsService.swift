// DiagnosticsService.swift
//
// On-device crash & diagnostics collection via MetricKit — no third-party SDK
// and no network. MetricKit delivers crash / hang / CPU-exception / disk-write
// payloads (batched, on the next launch). We log a summary through os.Logger and
// persist the raw payloads under Application Support so they can be inspected on
// device. Nothing is transmitted — diagnostics stay on the device, consistent
// with the app's on-device-data posture. To ship diagnostics to a backend later,
// upload the files returned by `recentPayloadFiles()`.

import Foundation
import MetricKit
import os

/// `nonisolated` so MetricKit can invoke the subscriber callbacks off the main
/// thread (the project defaults to `@MainActor` isolation). State is kept in
/// immutable `static let`s + a serial IO queue, so the type is safely `Sendable`.
nonisolated final class DiagnosticsService: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {

    static let shared = DiagnosticsService()

    private static let log = Logger(subsystem: "com.jetsetter.pro", category: "diagnostics")
    private static let ioQueue = DispatchQueue(label: "com.jetsetter.pro.diagnostics")
    private static let maxStoredFiles = 30

    private override init() { super.init() }

    /// Register with MetricKit. Call once, early in app launch.
    func start() {
        MXMetricManager.shared.add(self)
        Self.log.info("MetricKit diagnostics subscriber registered")
    }

    // MARK: - MXMetricManagerSubscriber (invoked off the main thread)

    func didReceive(_ payloads: [MXMetricPayload]) {
        Self.store(payloads.map { $0.jsonRepresentation() }, kind: "metric")
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let cpu = payload.cpuExceptionDiagnostics?.count ?? 0
            let disk = payload.diskWriteExceptionDiagnostics?.count ?? 0
            if crashes + hangs + cpu + disk > 0 {
                Self.log.error("MetricKit diagnostics — crashes:\(crashes) hangs:\(hangs) cpu:\(cpu) diskWrites:\(disk)")
            }
        }
        Self.store(payloads.map { $0.jsonRepresentation() }, kind: "diagnostic")
    }

    // MARK: - Device-local persistence

    /// Persisted payload files, newest first (e.g. for a Settings debug view).
    func recentPayloadFiles() -> [URL] {
        Self.sortedFiles(newestFirst: true)
    }

    private static func directory() -> URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("Diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func store(_ payloads: [Data], kind: String) {
        guard !payloads.isEmpty else { return }
        ioQueue.async {
            guard let dir = directory() else { return }
            let stamp = Int(Date().timeIntervalSince1970)
            for (index, data) in payloads.enumerated() {
                let url = dir.appendingPathComponent("\(kind)-\(stamp)-\(index).json")
                try? data.write(to: url, options: [.atomic, .completeFileProtection])
            }
            trim(in: dir, keeping: maxStoredFiles)
        }
    }

    private static func sortedFiles(newestFirst: Bool) -> [URL] {
        guard let dir = directory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]) else { return [] }
        return files.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return newestFirst ? da > db : da < db
        }
    }

    private static func trim(in dir: URL, keeping limit: Int) {
        let files = sortedFiles(newestFirst: false)
        guard files.count > limit else { return }
        for url in files.prefix(files.count - limit) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
