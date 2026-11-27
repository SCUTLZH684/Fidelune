import Foundation
import os

final class DiagnosticsLogger: DiagnosticsSink {
    static let shared = DiagnosticsLogger()

    private let osLog = Logger(subsystem: "io.github.scutlzh684.fideluneBass", category: "audio")
    private let queue = DispatchQueue(label: "io.github.scutlzh684.fidelune.diagnostics", qos: .utility)
    private var fileHandle: FileHandle?
    private(set) var logFileURL: URL?
    private var ringBuffer: [[String: Any]] = []
    private let maxRingEntries = 500
    private let dateFormatter: ISO8601DateFormatter

    init() {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.dateFormatter = fmt
    }

    func prepareStorage() -> URL? {
        queue.sync {
            if let existing = logFileURL {
                return existing
            }
            let fm = FileManager.default
            guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
                return nil
            }
            let musicDir = docs.appendingPathComponent("Music", isDirectory: true)
            let exportsDir = docs.appendingPathComponent("Exports", isDirectory: true)
            try? fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
            try? fm.createDirectory(at: exportsDir, withIntermediateDirectories: true)

            let fileURL = docs.appendingPathComponent("fidelune-bass-diagnostics.jsonl")
            if !fm.fileExists(atPath: fileURL.path) {
                try? Data().write(to: fileURL)
            }
            if let fh = try? FileHandle(forWritingTo: fileURL) {
                _ = try? fh.seekToEnd()
                fileHandle = fh
            }
            logFileURL = fileURL
            return fileURL
        }
    }

    func log(event: String, category: String = "audio", message: String, fields: [String: Any] = [:]) {
        let now = Date()
        let entry: [String: Any] = [
            "timestamp": dateFormatter.string(from: now),
            "unixTime": now.timeIntervalSince1970,
            "uptimeSeconds": ProcessInfo.processInfo.systemUptime,
            "category": category,
            "event": event,
            "message": message,
            "fields": fields,
            "memoryBytes": Self.currentMemoryFootprintBytes(),
        ]

        osLog.notice("FIDELUNE_BASS [\(category, privacy: .public)] \(event, privacy: .public): \(message, privacy: .public)")

        queue.async { [weak self] in
            guard let self else { return }
            self.ringBuffer.append(entry)
            if self.ringBuffer.count > self.maxRingEntries {
                self.ringBuffer.removeFirst(self.ringBuffer.count - self.maxRingEntries)
            }
            guard let fh = self.fileHandle,
                  JSONSerialization.isValidJSONObject(entry),
                  var line = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else {
                return
            }
            line.append(0x0A)
            try? fh.write(contentsOf: line)
        }
    }

    func recentEvents(limit: Int = 200) -> [[String: Any]] {
        queue.sync {
            if ringBuffer.count <= limit {
                return ringBuffer
            }
            return Array(ringBuffer.suffix(limit))
        }
    }

    func exportBundle(reportMarkdown: String, reportJson: String) -> URL? {
        queue.sync {
            let fm = FileManager.default
            guard let docs = try? fm.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else {
                return nil
            }
            let exportsDir = docs.appendingPathComponent("Exports", isDirectory: true)
            try? fm.createDirectory(at: exportsDir, withIntermediateDirectories: true)

            let stamp = Int(Date().timeIntervalSince1970)
            let folder = exportsDir.appendingPathComponent("fidelune-bass-report-\(stamp)", isDirectory: true)
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)

            let mdURL = folder.appendingPathComponent("acceptance-report.md")
            let jsonURL = folder.appendingPathComponent("acceptance-report.json")
            let logCopyURL = folder.appendingPathComponent("fidelune-bass-diagnostics.jsonl")

            try? reportMarkdown.write(to: mdURL, atomically: true, encoding: .utf8)
            try? reportJson.write(to: jsonURL, atomically: true, encoding: .utf8)

            if let sourceLog = logFileURL, fm.fileExists(atPath: sourceLog.path) {
                try? fileHandle?.synchronizeFile()
                try? fm.copyItem(at: sourceLog, to: logCopyURL)
            }
            return mdURL
        }
    }

    static func currentMemoryFootprintBytes() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.phys_footprint : 0
    }
}
