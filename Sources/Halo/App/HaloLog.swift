import Foundation

/// Dead-simple file logger. Self-signed/ad-hoc apps are filtered out of Console and
/// `log show`, so for dev tracing we append to `~/Library/Logs/Halo/halo.log` and
/// `tail -f` it. Cheap and best-effort; never throws into callers.
enum HaloLog {
    private static let url: URL? = {
        guard let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Logs/Halo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("halo.log")
    }()

    static func log(_ message: String) {
        guard let url else { return }
        let stamp = String(format: "%.3f", Date().timeIntervalSince1970)
        guard let data = "\(stamp)  \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: url)
        }
    }
}
