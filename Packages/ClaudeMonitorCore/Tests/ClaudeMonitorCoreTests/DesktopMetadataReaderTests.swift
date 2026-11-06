import Foundation
import Testing
@testable import ClaudeMonitorCore

struct DesktopMetadataReaderTests {
    @Test func findsNestedFileByHostSessionId() throws {
        let folder = try FixtureFolder()
        try folder.writeDesktopMetadata(hostSessionId: Fixture.idleSessionID)
        let reader = DesktopMetadataReader(rootDirectory: folder.desktopSessionsDirectory, reloadInterval: 0, now: Date.init)

        let metadata = reader.metadata(for: SessionID(Fixture.idleSessionID))

        #expect(metadata == DesktopSessionMetadata(
            title: "Card stop position fix",
            isArchived: false,
            lastActivityAt: Date(timeIntervalSince1970: 1_793_924_252.282)
        ))
    }

    @Test func readsFileAgainWhenModificationTimeChanges() throws {
        let folder = try FixtureFolder()
        let file = try folder.writeDesktopMetadata(hostSessionId: Fixture.idleSessionID, overrides: ["title": "First"])
        let reader = DesktopMetadataReader(rootDirectory: folder.desktopSessionsDirectory, reloadInterval: 0, now: Date.init)
        #expect(reader.metadata(for: SessionID(Fixture.idleSessionID))?.title == "First")

        try folder.writeDesktopMetadata(hostSessionId: Fixture.idleSessionID, overrides: ["title": "Second"])
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(10)],
            ofItemAtPath: file.path
        )

        #expect(reader.metadata(for: SessionID(Fixture.idleSessionID))?.title == "Second")
    }

    @Test func returnsNilForMissingOrUnsafeIdentifier() throws {
        let folder = try FixtureFolder()
        let reader = DesktopMetadataReader(rootDirectory: folder.desktopSessionsDirectory, reloadInterval: 0, now: Date.init)

        #expect(reader.metadata(for: SessionID(Fixture.idleSessionID)) == nil)
        #expect(reader.metadata(for: SessionID("local_../../etc")) == nil)
        #expect(reader.metadata(for: SessionID("pid-26719")) == nil)
    }

    @Test func findsFileCreatedAfterFirstMiss() throws {
        let folder = try FixtureFolder()
        let reader = DesktopMetadataReader(rootDirectory: folder.desktopSessionsDirectory, reloadInterval: 0, now: Date.init)
        #expect(reader.metadata(for: SessionID(Fixture.idleSessionID)) == nil)

        try folder.writeDesktopMetadata(hostSessionId: Fixture.idleSessionID, overrides: ["isArchived": true])

        #expect(reader.metadata(for: SessionID(Fixture.idleSessionID))?.isArchived == true)
    }
}
