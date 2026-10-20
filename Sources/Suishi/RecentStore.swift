import Foundation
import SQLite3
import MediaCore

struct RecentContent: Equatable {
    var url: String
    var title: String
    var seconds: Double
    var link: BilibiliVideoLink? {
        guard case .video(let value) = try? BilibiliLinkInput.parse(url) else { return nil }
        return value
    }
}

/// A small, versioned SQLite store. No credentials or per-frame camera data enter it.
/// Only this type knows SQL; content and rendering receive value objects.
@MainActor final class RecentStore {
    private var database: OpaquePointer?
    private(set) var issue: String?
    init(url: URL? = nil, inMemory: Bool = false) {
        do {
            let path: String
            if inMemory { path = ":memory:" }
            else {
                let location = try url ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("Suishi", isDirectory: true).appendingPathComponent("Library.sqlite")
                try FileManager.default.createDirectory(at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
                path = location.path
            }
            guard sqlite3_open_v2(path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw StoreError.failed }
            sqlite3_busy_timeout(database, 200)
            let version: Int32 = try statement("PRAGMA user_version") { query in
                guard sqlite3_step(query) == SQLITE_ROW else { throw StoreError.failed }
                return sqlite3_column_int(query, 0)
            }
            guard version <= 1 else { throw StoreError.newerSchema }
            try execute("PRAGMA journal_mode=WAL")
            try execute("BEGIN IMMEDIATE")
            do {
                try execute("CREATE TABLE IF NOT EXISTS recent_content (id INTEGER PRIMARY KEY CHECK(id = 1), source TEXT NOT NULL, url TEXT NOT NULL, title TEXT NOT NULL, seconds REAL NOT NULL DEFAULT 0, updated_at REAL NOT NULL)")
                if version == 0 { try execute("PRAGMA user_version=1") }
                try execute("COMMIT")
            } catch { try? execute("ROLLBACK"); throw error }
        } catch {
            if let database { sqlite3_close(database) }; database = nil
            issue = "观看记录暂时无法保存，播放不受影响。"
        }
    }
    deinit { if let database { sqlite3_close(database) } }
    func load() -> RecentContent? {
        guard database != nil else { return nil }
        do {
            return try statement("SELECT url,title,seconds FROM recent_content WHERE id=1 AND source='bilibili'") { query in
                let result = sqlite3_step(query)
                if result == SQLITE_DONE { return nil }
                guard result == SQLITE_ROW, let rawURL = sqlite3_column_text(query, 0), let rawTitle = sqlite3_column_text(query, 1) else { throw StoreError.failed }
                let seconds = sqlite3_column_double(query, 2)
                let item = RecentContent(url: String(cString: rawURL), title: String(cString: rawTitle), seconds: seconds.isFinite ? max(0, seconds) : 0)
                return item.link != nil ? item : nil
            }
        } catch { issue = "无法读取上次观看记录。"; return nil }
    }
    @discardableResult func save(_ item: RecentContent) -> Bool {
        guard database != nil, item.link != nil else { return false }
        do {
            try statement("INSERT INTO recent_content(id,source,url,title,seconds,updated_at) VALUES(1,'bilibili',?,?,?,?) ON CONFLICT(id) DO UPDATE SET source=excluded.source,url=excluded.url,title=excluded.title,seconds=excluded.seconds,updated_at=excluded.updated_at") { query in
                let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
                guard sqlite3_bind_text(query, 1, item.url, -1, transient) == SQLITE_OK,
                      sqlite3_bind_text(query, 2, item.title, -1, transient) == SQLITE_OK,
                      sqlite3_bind_double(query, 3, item.seconds.isFinite ? max(0, item.seconds) : 0) == SQLITE_OK,
                      sqlite3_bind_double(query, 4, Date().timeIntervalSince1970) == SQLITE_OK,
                      sqlite3_step(query) == SQLITE_DONE else { throw StoreError.failed }
            }
            issue = nil
            return true
        } catch { issue = "观看记录保存失败，播放不受影响。"; return false }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw StoreError.failed }
    }
    private func statement<T>(_ sql: String, body: (OpaquePointer) throws -> T) throws -> T {
        var query: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &query, nil) == SQLITE_OK, let query else { throw StoreError.failed }
        defer { sqlite3_finalize(query) }
        return try body(query)
    }
    private enum StoreError: Error { case failed, newerSchema }
}
