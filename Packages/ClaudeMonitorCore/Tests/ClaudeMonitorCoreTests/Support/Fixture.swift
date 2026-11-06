import Foundation

enum Fixture {
    /// `procStart` of every session fixture: "Thu Nov  5 23:12:54 2026" in UTC.
    static let processStart = Date(timeIntervalSince1970: 1_793_920_374)

    static let idleSessionID = "local_4e4528cf-0000-4111-a026-d33f3d7bd507"
    static let busySessionID = "local_c0337ec5-0000-4ebc-9aec-589c6c9f2db4"
    static let waitingSessionID = "local_a8d8f3ea-0000-4049-a019-7a9eceea89e4"
    static let unknownStatusSessionID = "local_c78eb17c-0000-481f-9572-238fb1c3830e"

    static func url(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return url
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }

    static func object(_ name: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data(name)) as? [String: Any] else {
            throw FixtureError.notAnObject(name)
        }
        return object
    }

    /// Epoch milliseconds for a test time offset in seconds.
    static func epochMilliseconds(_ seconds: TimeInterval) -> Int64 {
        Int64((baseTime.timeIntervalSince1970 + seconds) * 1000)
    }

    static func date(_ seconds: TimeInterval) -> Date {
        baseTime.addingTimeInterval(seconds)
    }

    static let baseTime = Date(timeIntervalSince1970: 1_793_924_000)
}

enum FixtureError: Error {
    case missing(String)
    case notAnObject(String)
}
