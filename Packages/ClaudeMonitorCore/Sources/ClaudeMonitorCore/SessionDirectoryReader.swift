import Foundation

/// Whether the session files have a format that this version of the app knows.
public enum SessionFormatSupport: Equatable, Sendable {
    case supported
    case unsupported(version: String?)
}

struct SessionDirectoryScan {
    var records: [SessionRecord]
    var formatSupport: SessionFormatSupport
}

/// Reads all `<pid>.json` files and keeps the last good state of each file.
final class SessionDirectoryReader {
    private let directory: URL
    private let fileManager: FileManager
    private var lastGoodResults: [String: SessionFileParseResult] = [:]

    init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    func read() -> SessionDirectoryScan {
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        let sessionFileNames = names.filter { $0.hasSuffix(".json") }

        var records: [SessionRecord] = []
        var knownFileCount = 0
        var unsupportedVersions: [String?] = []
        var goodResults: [String: SessionFileParseResult] = [:]

        for name in sessionFileNames {
            let data = fileManager.contents(atPath: directory.appendingPathComponent(name).path)
            var result = data.map(SessionFileParser.parse) ?? .unreadable
            if let lastGood = lastGoodResults[name], Self.isIncomplete(result) {
                result = lastGood
            }

            switch result {
            case .session(let record):
                records.append(record)
                knownFileCount += 1
                goodResults[name] = result
            case .spare:
                knownFileCount += 1
                goodResults[name] = result
            case .unsupported(let version):
                unsupportedVersions.append(version)
            case .unreadable:
                break
            }
        }
        lastGoodResults = goodResults

        let formatSupport: SessionFormatSupport
        if knownFileCount == 0, !unsupportedVersions.isEmpty {
            formatSupport = .unsupported(version: Self.newestVersion(unsupportedVersions))
        } else {
            formatSupport = .supported
        }
        return SessionDirectoryScan(records: records, formatSupport: formatSupport)
    }

    /// A partial write, or a file that a running process rewrites in more than one step.
    private static func isIncomplete(_ result: SessionFileParseResult) -> Bool {
        switch result {
        case .unreadable, .unsupported: true
        case .session, .spare: false
        }
    }

    private static func newestVersion(_ versions: [String?]) -> String? {
        versions.compactMap { $0 }.max { $0.compare($1, options: .numeric) == .orderedAscending }
    }
}
