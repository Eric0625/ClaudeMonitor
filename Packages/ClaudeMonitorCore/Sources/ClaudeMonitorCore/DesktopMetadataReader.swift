import Foundation

/// Fields from the Claude app's own file for a session.
public struct DesktopSessionMetadata: Equatable, Sendable {
    /// The title that the sidebar shows. The user can rename it.
    public var title: String?
    public var isArchived: Bool
    public var lastActivityAt: Date?
    /// The last time that the user opened the session in the Claude app.
    public var lastFocusedAt: Date?

    public init(title: String?, isArchived: Bool, lastActivityAt: Date?, lastFocusedAt: Date?) {
        self.title = title
        self.isArchived = isArchived
        self.lastActivityAt = lastActivityAt
        self.lastFocusedAt = lastFocusedAt
    }
}

/// Reads `<root>/<uuid>/<uuid>/<hostSessionId>.json`.
///
/// These files can be large. The reader caches the path and reads a file again only when its modification time changes.
public final class DesktopMetadataReader {
    private struct CachedFile {
        var url: URL
        var modificationDate: Date?
        var readAt: Date
        var metadata: DesktopSessionMetadata?
    }

    private let rootDirectory: URL
    private let reloadInterval: TimeInterval
    private let now: () -> Date
    private let fileManager: FileManager
    private var files: [SessionID: CachedFile] = [:]
    private var lastMissAt: [SessionID: Date] = [:]

    /// - Parameter reloadInterval: The minimum time between two reads of the same file.
    public init(
        rootDirectory: URL,
        reloadInterval: TimeInterval,
        now: @escaping () -> Date,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.reloadInterval = reloadInterval
        self.now = now
        self.fileManager = fileManager
    }

    public func metadata(for id: SessionID) -> DesktopSessionMetadata? {
        guard id.isDesktopSessionID else { return nil }

        if var cached = files[id] {
            guard let modificationDate = modificationDate(of: cached.url) else {
                files[id] = nil
                return locateAndRead(id)
            }
            if modificationDate != cached.modificationDate, now().timeIntervalSince(cached.readAt) >= reloadInterval {
                cached.readAt = now()
                if let metadata = Self.read(cached.url) {
                    cached.metadata = metadata
                    cached.modificationDate = modificationDate
                }
                files[id] = cached
            }
            return cached.metadata
        }
        return locateAndRead(id)
    }

    private func locateAndRead(_ id: SessionID) -> DesktopSessionMetadata? {
        if let missAt = lastMissAt[id], now().timeIntervalSince(missAt) < reloadInterval {
            return nil
        }
        guard let url = locate(id) else {
            lastMissAt[id] = now()
            return nil
        }
        lastMissAt[id] = nil
        let metadata = Self.read(url)
        files[id] = CachedFile(url: url, modificationDate: modificationDate(of: url), readAt: now(), metadata: metadata)
        return metadata
    }

    private func locate(_ id: SessionID) -> URL? {
        let fileName = "\(id.rawValue).json"
        for first in subdirectories(of: rootDirectory) {
            for second in subdirectories(of: first) {
                let candidate = second.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func subdirectories(of url: URL) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private static func read(_ url: URL) -> DesktopSessionMetadata? {
        guard
            let data = try? Data(contentsOf: url),
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return nil
        }
        return DesktopSessionMetadata(
            title: object["title"] as? String,
            isArchived: object["isArchived"] as? Bool ?? false,
            lastActivityAt: epochMillisecondsDate(object["lastActivityAt"]),
            lastFocusedAt: epochMillisecondsDate(object["lastFocusedAt"])
        )
    }

    private static func epochMillisecondsDate(_ value: Any?) -> Date? {
        (value as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
    }
}
