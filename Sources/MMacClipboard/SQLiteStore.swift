import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SQLiteStore {
    private var db: OpaquePointer?
    let imagesDirectory: URL

    init() throws {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let root = appSupport.appendingPathComponent("MMac-clipboard", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        imagesDirectory = root.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        let dbURL = root.appendingPathComponent("history.sqlite")
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLiteStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "无法打开数据库: \(String(cString: sqlite3_errmsg(db)))"])
        }
        try? execute("PRAGMA journal_mode=WAL;")
        try execute("""
        CREATE TABLE IF NOT EXISTS items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            text TEXT,
            image_path TEXT,
            image_w INTEGER,
            image_h INTEGER,
            hash TEXT NOT NULL,
            source_bundle_id TEXT,
            source_name TEXT,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_items_created ON items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_items_hash ON items(hash);
        """)
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - 查询

    func loadAll() -> [ClipboardItem] {
        let sql = """
        SELECT id, kind, text, image_path, image_w, image_h, hash, source_bundle_id, source_name, created_at
        FROM items ORDER BY created_at DESC, id DESC LIMIT 10000;
        """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }

        var items: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let kindRaw = String(cString: sqlite3_column_text(stmt, 1))
            let kind = ItemKind(rawValue: kindRaw) ?? .text
            let text = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            let imagePath = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let w = sqlite3_column_int(stmt, 4)
            let h = sqlite3_column_int(stmt, 5)
            let hash = sqlite3_column_text(stmt, 6).map { String(cString: $0) } ?? ""
            let bundleID = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
            let sourceName = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 9))
            items.append(ClipboardItem(
                id: id, kind: kind, text: text, imagePath: imagePath,
                pixelWidth: w > 0 ? Int(w) : nil, pixelHeight: h > 0 ? Int(h) : nil,
                sourceBundleID: bundleID, sourceName: sourceName,
                createdAt: createdAt, contentHash: hash
            ))
        }
        return items
    }

    // MARK: - 写入

    enum UpsertResult {
        case inserted(Int64)
        /// 已存在同内容条目：只把它挪到顶部，返回已存在条目的 id
        case touched(Int64)
    }

    func upsert(_ payload: CapturePayload) throws -> UpsertResult {
        if let existingID = idForHash(payload.contentHash) {
            try execute("UPDATE items SET created_at = \(payload.capturedAt.timeIntervalSince1970) WHERE id = \(existingID);")
            return .touched(existingID)
        }

        let sql = """
        INSERT INTO items (kind, text, image_path, image_w, image_h, hash, source_bundle_id, source_name, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else {
            throw NSError(domain: "SQLiteStore", code: 2, userInfo: [NSLocalizedDescriptionKey: lastError])
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, payload.content.kindRaw, -1, SQLITE_TRANSIENT)
        switch payload.content {
        case .text(let text):
            sqlite3_bind_text(stmt, 2, text, -1, SQLITE_TRANSIENT)
            sqlite3_bind_null(stmt, 3)
            sqlite3_bind_null(stmt, 4)
            sqlite3_bind_null(stmt, 5)
        case .image(_, let width, let height):
            sqlite3_bind_null(stmt, 2)
            sqlite3_bind_text(stmt, 3, payload.imagePath ?? "", -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 4, Int32(width))
            sqlite3_bind_int(stmt, 5, Int32(height))
        }
        sqlite3_bind_text(stmt, 6, payload.contentHash, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 7, payload.sourceBundleID ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 8, payload.sourceName ?? "", -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 9, payload.capturedAt.timeIntervalSince1970)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "SQLiteStore", code: 3, userInfo: [NSLocalizedDescriptionKey: lastError])
        }
        return .inserted(sqlite3_last_insert_rowid(db))
    }

    /// 删除指定条目，返回其图片文件路径（若有）供调用方清理文件
    @discardableResult
    func delete(id: Int64) -> String? {
        let path = imagePath(for: id)
        try? execute("DELETE FROM items WHERE id = \(id);")
        return path
    }

    /// 超出上限的旧条目会被删除，返回被删条目的图片路径列表
    func prune(limit: Int) -> [String] {
        let sql = """
        SELECT id FROM items WHERE id NOT IN (
            SELECT id FROM items ORDER BY created_at DESC, id DESC LIMIT \(limit)
        );
        """
        guard let stmt = prepare(sql) else { return [] }
        var paths: [String] = []
        var ids: [Int64] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            ids.append(sqlite3_column_int64(stmt, 0))
        }
        sqlite3_finalize(stmt)
        for id in ids {
            if let path = delete(id: id) { paths.append(path) }
        }
        return paths
    }

    /// 清空全部历史，返回所有图片路径
    func clearAll() -> [String] {
        let paths = loadAll().compactMap(\.imagePath)
        try? execute("DELETE FROM items;")
        return paths
    }

    // MARK: - 私有

    private var lastError: String {
        String(cString: sqlite3_errmsg(db))
    }

    private func idForHash(_ hash: String) -> Int64? {
        guard let stmt = prepare("SELECT id FROM items WHERE hash = ? LIMIT 1;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, hash, -1, SQLITE_TRANSIENT)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
    }

    private func imagePath(for id: Int64) -> String? {
        guard let stmt = prepare("SELECT image_path FROM items WHERE id = ?;") else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, id)
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_text(stmt, 0).map { String(cString: $0) } : nil
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            NSLog("SQLite prepare 失败: \(lastError) — \(sql)")
            return nil
        }
        return stmt
    }

    private func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK else {
            let message = errMsg.map { String(cString: $0) } ?? lastError
            sqlite3_free(errMsg)
            throw NSError(domain: "SQLiteStore", code: 4, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

