import Foundation
import SQLite3

enum NeteaseDatabaseStatus: Sendable {
    case waitingForPlayer, notConnected, checking, readable, permissionRequired, databaseMissing, unsupported, temporarilyUnavailable
}

struct NeteaseTrack {
    struct Identity: Equatable {
        let id: String
        let startedAt: Date
    }

    let identity: Identity
    let title: String?
    let artist: String?
    let album: String?
    let duration: TimeInterval?
    let artworkURL: URL?
}

enum NeteaseTrackDatabase {
    static let fileName = "sqlite_storage.sqlite3"

    enum Reading {
        case track(NeteaseTrack?)
        case failed(NeteaseDatabaseStatus)
    }

    static func read(in directory: URL, trackID: String? = nil) -> Reading {
        let url = directory.appending(path: fileName)
        // Check the file before asking SQLite to open it so the settings can distinguish
        // a missing database from macOS denying access to another app's container.
        do {
            let handle = try FileHandle(forReadingFrom: url)
            try handle.close()
        } catch {
            let error = error as NSError
            let posix = error.domain == NSPOSIXErrorDomain ? error : error.userInfo[NSUnderlyingErrorKey] as? NSError
            if posix?.domain == NSPOSIXErrorDomain, let code = posix?.code, [Int(EACCES), Int(EPERM)].contains(code) {
                return .failed(.permissionRequired)
            }
            switch CocoaError.Code(rawValue: error.code) {
            case .fileReadNoPermission: return .failed(.permissionRequired)
            case .fileNoSuchFile, .fileReadNoSuchFile: return .failed(.databaseMissing)
            default: return .failed(.temporarilyUnavailable)
            }
        }

        var connection: OpaquePointer?
        defer { sqlite3_close(connection) }
        let opened = sqlite3_open_v2(url.path, &connection, SQLITE_OPEN_READONLY, nil)
        guard opened == SQLITE_OK, let connection else { return .failed(status(for: opened, connection: connection)) }
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        let query = if trackID == nil {
            "SELECT id, playtime, jsonStr FROM historyTracks ORDER BY playtime DESC LIMIT 1"
        } else {
            "SELECT id, playtime, jsonStr FROM historyTracks WHERE id = ? LIMIT 1"
        }
        let prepared = sqlite3_prepare_v2(connection, query, -1, &statement, nil)
        guard prepared == SQLITE_OK else { return .failed(status(for: prepared, connection: connection)) }
        if let trackID {
            let bound = sqlite3_bind_text(statement, 1, trackID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard bound == SQLITE_OK else { return .failed(status(for: bound, connection: connection)) }
        }
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return .track(nil) }
        guard result == SQLITE_ROW else { return .failed(status(for: result, connection: connection)) }
        guard let id = sqlite3_column_text(statement, 0), let json = sqlite3_column_text(statement, 2),
              let object = (try? JSONSerialization.jsonObject(with: Data(String(cString: json).utf8))) as? [String: Any],
              let identifier = String(cString: id).nonBlank else { return .failed(.unsupported) }
        let playtime = sqlite3_column_int64(statement, 1)
        guard playtime > 0 else { return .failed(.unsupported) }
        let duration = ((object["duration"] ?? object["dt"]) as? NSNumber)?.doubleValue
        let album = (object["album"] ?? object["al"]) as? [String: Any]
        let artists = (object["artists"] ?? object["ar"]) as? [[String: Any]]
        var cover = (album?["picUrl"] as? String).flatMap { URLComponents(string: $0) }
        if cover?.scheme == "http" { cover?.scheme = "https" }
        return .track(NeteaseTrack(
            identity: .init(id: identifier, startedAt: Date(timeIntervalSince1970: Double(playtime) / 1_000)),
            title: (object["name"] as? String)?.nonBlank,
            artist: artists?.compactMap { ($0["name"] as? String)?.nonBlank }.joined(separator: " / ").nonBlank,
            album: (album?["name"] as? String)?.nonBlank,
            duration: duration.flatMap { $0.isFinite && $0 > 0 ? $0 / 1_000 : nil },
            artworkURL: cover?.url
        ))
    }

    private static func status(for result: Int32, connection: OpaquePointer?) -> NeteaseDatabaseStatus {
        if let connection, [EACCES, EPERM].contains(sqlite3_system_errno(connection)) { return .permissionRequired }
        switch result {
        case SQLITE_PERM, SQLITE_AUTH: return .permissionRequired
        case SQLITE_ERROR, SQLITE_NOTADB, SQLITE_CORRUPT: return .unsupported
        default: return .temporarilyUnavailable
        }
    }
}
