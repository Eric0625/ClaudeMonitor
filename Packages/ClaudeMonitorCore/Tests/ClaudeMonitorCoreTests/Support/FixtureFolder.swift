import Foundation

/// Temporary copy of `~/.claude/sessions` and the desktop session metadata folder.
final class FixtureFolder {
    let root: URL
    let sessionsDirectory: URL
    let desktopSessionsDirectory: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeMonitorTests-\(UUID().uuidString)", isDirectory: true)
        sessionsDirectory = root.appendingPathComponent("sessions", isDirectory: true)
        desktopSessionsDirectory = root.appendingPathComponent("claude-code-sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: desktopSessionsDirectory, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Writes `<pid>.json` from a fixture, where an `NSNull` override removes the key.
    func writeSession(_ fixture: String, pid: Int32, overrides: [String: Any] = [:]) throws {
        var object = try Fixture.object(fixture)
        object["pid"] = pid
        for (key, value) in overrides {
            object[key] = value is NSNull ? nil : value
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: sessionFile(pid: pid))
    }

    func writeRawSession(pid: Int32, contents: Data) throws {
        try contents.write(to: sessionFile(pid: pid))
    }

    func writeFile(named name: String, contents: Data) throws {
        try contents.write(to: sessionsDirectory.appendingPathComponent(name))
    }

    func removeSession(pid: Int32) throws {
        try FileManager.default.removeItem(at: sessionFile(pid: pid))
    }

    /// Writes `<uuid>/<uuid>/<hostSessionId>.json` like the Claude app does.
    @discardableResult
    func writeDesktopMetadata(hostSessionId: String, overrides: [String: Any] = [:]) throws -> URL {
        var object = try Fixture.object("desktop-metadata")
        object["sessionId"] = hostSessionId
        for (key, value) in overrides {
            object[key] = value is NSNull ? nil : value
        }
        let folder = desktopSessionsDirectory
            .appendingPathComponent("0fe5556a-0000-4e16-893b-2433fb9b5a44", isDirectory: true)
            .appendingPathComponent("02600c9e-0000-4714-9807-ac479a4f582b", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(hostSessionId).json")
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: file)
        return file
    }

    private func sessionFile(pid: Int32) -> URL {
        sessionsDirectory.appendingPathComponent("\(pid).json")
    }
}
