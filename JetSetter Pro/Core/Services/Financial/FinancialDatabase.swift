// File: Core/Services/Financial/FinancialDatabase.swift
//
// On-device SQLite store for the user's FINANCIAL data — expenses, currency-tracker
// expenses, and scanned receipts (OCR text + image bytes). This data is **device-only
// and is never synced to Supabase or any third-party API** (product/privacy decision;
// see SETUP-SUPABASE.md §3 and docs/ANDROID_SQLITE_FINANCIAL_SPEC.md).
//
// Built directly on the system `SQLite3` C library — no SwiftData / GRDB / SPM
// dependency (keeps the dependency surface minimal, matching SupabaseService's
// hand-rolled REST approach).
//
// CONCURRENCY: this is the low-level engine. It owns the single `sqlite3` handle and
// serializes **all** access through a private serial `DispatchQueue`, so it is safe to
// touch from any thread/actor and is marked `@unchecked Sendable`. `@MainActor`
// callers should prefer the async `FinancialStore` actor which wraps this; the handful
// of `nonisolated` synchronous callers that can't `await` (App Intents' `perform`,
// IRIS context/triggers, `TravelStore`) use this engine directly.
//
// AT REST: the DB lives in Application Support with `FileProtectionType.complete`
// (encrypted, unreadable while the device is locked) and is excluded from iCloud /
// iTunes backups, so financial data stays on this device only.

import Foundation
import SQLite3

// SQLite wants to know whether a bound string/blob is stable for the life of the
// statement (STATIC) or must be copied (TRANSIENT). We copy — the Swift buffers are
// transient — so bindings never dangle. `-1` is SQLITE_TRANSIENT.
//
// `nonisolated(unsafe)`: the project builds with `@MainActor` default isolation, which
// would otherwise pin this file-scope constant to the main actor. It's an immutable C
// function pointer read only from the DB queue, so opting it out is safe.
private nonisolated(unsafe) let SQLITE_TRANSIENT =
    unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Receipt (device-only)

/// A scanned receipt tied to an `Expense`. Holds the raw OCR text and, optionally,
/// the captured image bytes. Image bytes never leave the device — they live only in
/// this encrypted SQLite store.
nonisolated struct Receipt: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let expenseID: UUID
    var ocrText: String?
    var imageData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        expenseID: UUID,
        ocrText: String? = nil,
        imageData: Data? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.expenseID = expenseID
        self.ocrText = ocrText
        self.imageData = imageData
        self.createdAt = createdAt
    }
}

// MARK: - FinancialDatabase

// `nonisolated`: the project builds with `@MainActor` default isolation. This engine is
// deliberately actor-agnostic — it's reached from the `FinancialStore` actor AND from
// nonisolated synchronous callers (App Intents, IRIS, TravelStore) — so it opts out of
// the default main-actor isolation and provides its own serial-queue safety instead.
nonisolated final class FinancialDatabase: @unchecked Sendable {

    /// Shared engine backed by the encrypted Application Support database.
    static let shared = FinancialDatabase()

    // Legacy UserDefaults keys the first-launch migration drains + deletes.
    static let legacyExpensesKey    = "jetsetter_expenses"
    static let legacyCurrencyPrefix = "jetsetter_currency_expenses_"

    private let queue = DispatchQueue(label: "com.jetsetter.financial.sqlite")
    private var db: OpaquePointer?
    private let defaults: UserDefaults
    private let migrationFlagKey: String

    /// - Parameters:
    ///   - url: database file location. Defaults to `Application Support/Financial/financial.sqlite`.
    ///   - defaults: UserDefaults used for the migration source + one-time flag (injectable for tests).
    ///   - migrationFlagKey: the "already migrated" flag key (injectable for tests).
    ///   - autoMigrate: run the UserDefaults→SQLite migration during init. Tests pass `false`
    ///     to drive migration explicitly.
    init(
        url: URL? = nil,
        defaults: UserDefaults = .standard,
        migrationFlagKey: String = "jetsetter_financial_sqlite_migrated_v1",
        autoMigrate: Bool = true
    ) {
        self.defaults = defaults
        self.migrationFlagKey = migrationFlagKey
        let location = url ?? Self.defaultDatabaseURL()
        queue.sync {
            openDatabase(at: location)
            createSchema()
        }
        if autoMigrate { migrateFromUserDefaultsIfNeeded() }
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Location + protection

    /// `Application Support/Financial/financial.sqlite`, created on demand. Falls back
    /// to a temporary directory if Application Support is somehow unavailable so the app
    /// degrades to an in-session store rather than crashing.
    private static func defaultDatabaseURL() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("Financial", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        applyDeviceOnlyProtection(to: dir)
        return dir.appendingPathComponent("financial.sqlite", isDirectory: false)
    }

    /// Marks a file/dir as complete-protection (encrypted, device-locked) and excluded
    /// from backups, so financial data can only ever live on this unlocked device.
    private static func applyDeviceOnlyProtection(to url: URL) {
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? mutable.setResourceValues(values)
    }

    // MARK: - Open + schema

    private func openDatabase(at url: URL) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        if sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK {
            db = handle
            // Foreign keys let receipts cascade-delete with their expense.
            sqlite3_exec(handle, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        } else {
            db = nil
        }
        // The `:memory:` sentinel + temp fallbacks have no on-disk file to protect.
        if url.isFileURL && url.path != ":memory:" {
            Self.applyDeviceOnlyProtection(to: url)
        }
    }

    private func createSchema() {
        let ddl = """
        CREATE TABLE IF NOT EXISTS expenses (
            id               TEXT PRIMARY KEY,
            amount           REAL NOT NULL,
            currency         TEXT NOT NULL,
            category         TEXT NOT NULL,
            merchant         TEXT NOT NULL,
            date             REAL NOT NULL,
            notes            TEXT,
            receipt_text     TEXT,
            mileage_distance REAL
        );
        CREATE TABLE IF NOT EXISTS currency_expenses (
            id                  TEXT PRIMARY KEY,
            trip_id             TEXT NOT NULL,
            amount              REAL NOT NULL,
            currency            TEXT NOT NULL,
            converted_amount    REAL,
            home_currency       TEXT NOT NULL,
            category            TEXT NOT NULL,
            description         TEXT NOT NULL,
            date                REAL NOT NULL,
            receipt_image_path  TEXT
        );
        CREATE TABLE IF NOT EXISTS receipts (
            id          TEXT PRIMARY KEY,
            expense_id  TEXT NOT NULL,
            ocr_text    TEXT,
            image_data  BLOB,
            created_at  REAL NOT NULL,
            FOREIGN KEY(expense_id) REFERENCES expenses(id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS idx_currency_expenses_trip ON currency_expenses(trip_id);
        CREATE INDEX IF NOT EXISTS idx_receipts_expense ON receipts(expense_id);
        """
        sqlite3_exec(db, ddl, nil, nil, nil)
    }

    // MARK: - Expenses (public, thread-safe)

    func allExpenses() -> [Expense] { queue.sync { allExpensesUnsafe() } }

    /// True when the expenses table has no rows. Used by demo seeding to decide
    /// whether it may seed sample data WITHOUT clobbering real (e.g. freshly
    /// migrated) expenses.
    func isExpensesEmpty() -> Bool {
        queue.sync {
            guard let stmt = prepare("SELECT 1 FROM expenses LIMIT 1;") else { return true }
            defer { sqlite3_finalize(stmt) }
            return sqlite3_step(stmt) != SQLITE_ROW
        }
    }

    /// Inserts or updates a single expense, then notifies observers so any visible
    /// tracker with a stale in-memory copy reloads instead of later clobbering this
    /// out-of-band write. This is the granular writer used by every per-item add/edit
    /// (view-models, Siri/App Intents via TravelStore, IRIS).
    func upsertExpense(_ expense: Expense) {
        queue.sync { _ = insertExpenseUnsafe(expense) }
        NotificationCenter.default.post(name: .jetSetterExpensesChanged, object: nil)
    }

    func deleteExpense(id: UUID) {
        queue.sync {
            // Belt-and-suspenders: purge the receipt(s) for this expense first, so the
            // image BLOB is never orphaned even if FK cascade isn't enforced (older
            // SQLite, or a failed `PRAGMA foreign_keys = ON`). The FK ON DELETE CASCADE
            // on `receipts` covers this too.
            if let rstmt = prepare("DELETE FROM receipts WHERE expense_id = ?;") {
                bindText(rstmt, 1, id.uuidString)
                sqlite3_step(rstmt)
                sqlite3_finalize(rstmt)
            }
            guard let stmt = prepare("DELETE FROM expenses WHERE id = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id.uuidString)
            sqlite3_step(stmt)
        }
        NotificationCenter.default.post(name: .jetSetterExpensesChanged, object: nil)
    }

    /// Replaces the entire expense set atomically (mirrors the old "encode the whole
    /// array to UserDefaults" save semantics). Reserved for legitimate BULK operations
    /// only — demo seeding and migration — never for a single add/edit/delete (those use
    /// the granular `upsertExpense`/`deleteExpense`, which don't destroy out-of-band
    /// writes). Intentionally does NOT post `.jetSetterExpensesChanged`, since it runs at
    /// launch before any tracker view is on screen.
    func replaceAllExpenses(_ expenses: [Expense]) {
        queue.sync {
            execUnsafe("BEGIN;")
            // Purge receipts first so their image BLOBs aren't orphaned by wiping the
            // expenses they belong to.
            execUnsafe("DELETE FROM receipts;")
            execUnsafe("DELETE FROM expenses;")
            for expense in expenses { _ = insertExpenseUnsafe(expense) }
            execUnsafe("COMMIT;")
        }
    }

    private func allExpensesUnsafe() -> [Expense] {
        let sql = """
        SELECT id, amount, currency, category, merchant, date, notes, receipt_text, mileage_distance
        FROM expenses;
        """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        var result: [Expense] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(stmt, 0) ?? ""),
                  let category = ExpenseCategory(rawValue: columnText(stmt, 3) ?? "") else { continue }
            let expense = Expense(
                id: id,
                amount: sqlite3_column_double(stmt, 1),
                currency: columnText(stmt, 2) ?? "USD",
                category: category,
                merchant: columnText(stmt, 4) ?? "",
                date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5)),
                notes: columnText(stmt, 6),
                receiptText: columnText(stmt, 7),
                mileageDistance: columnDouble(stmt, 8)
            )
            result.append(expense)
        }
        return result
    }

    /// Returns `true` only when the row was actually written (`sqlite3_step == SQLITE_DONE`).
    /// The migration relies on this: it must NOT delete a legacy UserDefaults key unless
    /// its rows verifiably landed in SQLite (disk-full / locked / corrupt returns `false`).
    @discardableResult
    private func insertExpenseUnsafe(_ expense: Expense) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO expenses
        (id, amount, currency, category, merchant, date, notes, receipt_text, mileage_distance)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return false }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, expense.id.uuidString)
        sqlite3_bind_double(stmt, 2, expense.amount)
        bindText(stmt, 3, expense.currency)
        bindText(stmt, 4, expense.category.rawValue)
        bindText(stmt, 5, expense.merchant)
        sqlite3_bind_double(stmt, 6, expense.date.timeIntervalSince1970)
        bindOptionalText(stmt, 7, expense.notes)
        bindOptionalText(stmt, 8, expense.receiptText)
        bindOptionalDouble(stmt, 9, expense.mileageDistance)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    // MARK: - Currency expenses (public, thread-safe)

    func allCurrencyExpenses(tripId: UUID) -> [CurrencyExpense] {
        queue.sync { currencyExpensesUnsafe(tripId: tripId) }
    }

    /// Granular per-item writer. Notifies observers so a visible currency tracker with a
    /// stale in-memory copy reloads rather than clobbering this write on its next save.
    func upsertCurrencyExpense(_ expense: CurrencyExpense) {
        queue.sync { _ = insertCurrencyExpenseUnsafe(expense) }
        NotificationCenter.default.post(name: .jetSetterExpensesChanged, object: nil)
    }

    func deleteCurrencyExpense(id: UUID) {
        queue.sync {
            guard let stmt = prepare("DELETE FROM currency_expenses WHERE id = ?;") else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, id.uuidString)
            sqlite3_step(stmt)
        }
        NotificationCenter.default.post(name: .jetSetterExpensesChanged, object: nil)
    }

    /// Replaces the currency expenses for a single trip atomically. BULK operation
    /// (demo seeding / migration) — single edits use the granular writers above.
    func replaceCurrencyExpenses(_ expenses: [CurrencyExpense], tripId: UUID) {
        queue.sync {
            execUnsafe("BEGIN;")
            if let stmt = prepare("DELETE FROM currency_expenses WHERE trip_id = ?;") {
                bindText(stmt, 1, tripId.uuidString)
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            for expense in expenses { _ = insertCurrencyExpenseUnsafe(expense) }
            execUnsafe("COMMIT;")
        }
    }

    private func currencyExpensesUnsafe(tripId: UUID) -> [CurrencyExpense] {
        let sql = """
        SELECT id, trip_id, amount, currency, converted_amount, home_currency,
               category, description, date, receipt_image_path
        FROM currency_expenses WHERE trip_id = ?;
        """
        guard let stmt = prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, tripId.uuidString)
        var result: [CurrencyExpense] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let id = UUID(uuidString: columnText(stmt, 0) ?? ""),
                  let trip = UUID(uuidString: columnText(stmt, 1) ?? ""),
                  let category = SpendCategory(rawValue: columnText(stmt, 6) ?? "") else { continue }
            let expense = CurrencyExpense(
                id: id,
                tripId: trip,
                amount: sqlite3_column_double(stmt, 2),
                currency: columnText(stmt, 3) ?? "USD",
                convertedAmount: columnDouble(stmt, 4),
                homeCurrency: columnText(stmt, 5) ?? "USD",
                category: category,
                description: columnText(stmt, 7) ?? "",
                date: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 8)),
                receiptImagePath: columnText(stmt, 9)
            )
            result.append(expense)
        }
        return result
    }

    /// Returns `true` only when the row was actually written (`sqlite3_step == SQLITE_DONE`),
    /// so the migration can verify success before deleting the legacy source key.
    @discardableResult
    private func insertCurrencyExpenseUnsafe(_ expense: CurrencyExpense) -> Bool {
        let sql = """
        INSERT OR REPLACE INTO currency_expenses
        (id, trip_id, amount, currency, converted_amount, home_currency,
         category, description, date, receipt_image_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        guard let stmt = prepare(sql) else { return false }
        defer { sqlite3_finalize(stmt) }
        bindText(stmt, 1, expense.id.uuidString)
        bindText(stmt, 2, expense.tripId.uuidString)
        sqlite3_bind_double(stmt, 3, expense.amount)
        bindText(stmt, 4, expense.currency)
        bindOptionalDouble(stmt, 5, expense.convertedAmount)
        bindText(stmt, 6, expense.homeCurrency)
        bindText(stmt, 7, expense.category.rawValue)
        bindText(stmt, 8, expense.description)
        sqlite3_bind_double(stmt, 9, expense.date.timeIntervalSince1970)
        bindOptionalText(stmt, 10, expense.receiptImagePath)
        return sqlite3_step(stmt) == SQLITE_DONE
    }

    // MARK: - Receipts (public, thread-safe)

    func upsertReceipt(_ receipt: Receipt) {
        queue.sync {
            let sql = """
            INSERT OR REPLACE INTO receipts (id, expense_id, ocr_text, image_data, created_at)
            VALUES (?, ?, ?, ?, ?);
            """
            guard let stmt = prepare(sql) else { return }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, receipt.id.uuidString)
            bindText(stmt, 2, receipt.expenseID.uuidString)
            bindOptionalText(stmt, 3, receipt.ocrText)
            bindOptionalBlob(stmt, 4, receipt.imageData)
            sqlite3_bind_double(stmt, 5, receipt.createdAt.timeIntervalSince1970)
            sqlite3_step(stmt)
        }
    }

    func receipt(forExpenseID expenseID: UUID) -> Receipt? {
        queue.sync {
            let sql = """
            SELECT id, expense_id, ocr_text, image_data, created_at
            FROM receipts WHERE expense_id = ? ORDER BY created_at DESC LIMIT 1;
            """
            guard let stmt = prepare(sql) else { return nil }
            defer { sqlite3_finalize(stmt) }
            bindText(stmt, 1, expenseID.uuidString)
            guard sqlite3_step(stmt) == SQLITE_ROW,
                  let id = UUID(uuidString: columnText(stmt, 0) ?? ""),
                  let expID = UUID(uuidString: columnText(stmt, 1) ?? "") else { return nil }
            return Receipt(
                id: id,
                expenseID: expID,
                ocrText: columnText(stmt, 2),
                imageData: columnBlob(stmt, 3),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 4))
            )
        }
    }

    // MARK: - Account deletion / clear

    /// Wipes every financial table. Called on account deletion and "Clear Local Data".
    func wipeAllFinancialData() {
        queue.sync {
            // Receipts first (their image BLOBs), then the expense rows they reference.
            execUnsafe("DELETE FROM receipts;")
            execUnsafe("DELETE FROM currency_expenses;")
            execUnsafe("DELETE FROM expenses;")
        }
    }

    // MARK: - First-launch migration (UserDefaults → SQLite)

    /// Drains any pre-existing financial data out of UserDefaults into SQLite exactly
    /// once, then deletes those keys so financial data is never written to UserDefaults
    /// again. Idempotent — guarded by a one-time flag.
    ///
    /// SAFETY: this is the only path that both writes SQLite *and* destroys the legacy
    /// copy, so it deletes a source key ONLY after verifying the corresponding rows
    /// actually landed, and it sets the one-time flag ONLY when the whole run succeeded.
    /// A failed open (`db == nil`), an undecodable blob, or a failed `sqlite3_step`
    /// (disk-full / locked / corrupt) leaves the source key AND the flag untouched, so
    /// the next launch retries instead of silently losing the user's expense history.
    func migrateFromUserDefaultsIfNeeded() {
        guard !defaults.bool(forKey: migrationFlagKey) else { return }

        // No usable database (open failed) → there is nowhere safe to move the data.
        // Abort WITHOUT deleting any key or setting the flag so a later launch retries.
        guard queue.sync(execute: { db != nil }) else { return }

        var allSucceeded = true

        // ── Legacy [Expense] blob (single key) ──────────────────────────────────
        if let data = defaults.data(forKey: Self.legacyExpensesKey) {
            // Raw Data is present, so it MUST decode AND insert before we delete it.
            // `decodeExpenses` returns [] on ANY decode failure and we can't distinguish
            // that from a genuinely empty array, so an empty result is treated as a
            // FAILURE: preserve the key and retry rather than risk dropping data.
            let expenses = Self.decodeExpenses(data)
            if expenses.isEmpty {
                allSucceeded = false
            } else {
                let inserted = queue.sync { () -> Bool in
                    var ok = true
                    for expense in expenses { ok = insertExpenseUnsafe(expense) && ok }
                    return ok
                }
                if inserted {
                    defaults.removeObject(forKey: Self.legacyExpensesKey)   // safe: rows landed
                } else {
                    allSucceeded = false                                    // keep the key
                }
            }
        }
        // (key absent → nothing to migrate for expenses; not a failure)

        // ── Legacy per-trip currency expenses (one key per trip) ────────────────
        for key in defaults.dictionaryRepresentation().keys
        where key.hasPrefix(Self.legacyCurrencyPrefix) {
            guard let data = defaults.data(forKey: key) else { continue }
            let expenses = Self.decodeCurrencyExpenses(data)
            if expenses.isEmpty {
                allSucceeded = false
                continue
            }
            let inserted = queue.sync { () -> Bool in
                var ok = true
                for expense in expenses { ok = insertCurrencyExpenseUnsafe(expense) && ok }
                return ok
            }
            if inserted {
                defaults.removeObject(forKey: key)   // safe: rows landed
            } else {
                allSucceeded = false                 // keep the key
            }
        }

        // Only claim the one-time migration is done when every present key migrated and
        // was safely removed. A partial/failed run leaves the flag unset so the next
        // launch retries (inserts are INSERT OR REPLACE, so retries are idempotent).
        if allSucceeded {
            defaults.set(true, forKey: migrationFlagKey)
        }
    }

    /// Tolerant decode of legacy `[Expense]` blobs. Historically these were written with
    /// two different date strategies across the codebase (ISO-8601 via TravelStore, the
    /// default numeric strategy via ExpenseViewModel), so try ISO-8601 first and fall
    /// back to the default rather than silently dropping data.
    static func decodeExpenses(_ data: Data) -> [Expense] {
        let iso = JSONDecoder(); iso.dateDecodingStrategy = .iso8601
        if let v = try? iso.decode([Expense].self, from: data) { return v }
        return (try? JSONDecoder().decode([Expense].self, from: data)) ?? []
    }

    static func decodeCurrencyExpenses(_ data: Data) -> [CurrencyExpense] {
        let iso = JSONDecoder(); iso.dateDecodingStrategy = .iso8601
        if let v = try? iso.decode([CurrencyExpense].self, from: data) { return v }
        return (try? JSONDecoder().decode([CurrencyExpense].self, from: data)) ?? []
    }

    // MARK: - Low-level helpers (must run on `queue`)

    /// Runs a parameterless statement, returning whether SQLite accepted it
    /// (`SQLITE_OK`). Used for BEGIN/COMMIT/DELETE in the bulk paths so the exec
    /// helpers report success/failure like the step-based ones.
    @discardableResult
    private func execUnsafe(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func prepare(_ sql: String) -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let stmt { sqlite3_finalize(stmt) }
            return nil
        }
        return stmt
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func bindOptionalDouble(_ stmt: OpaquePointer?, _ index: Int32, _ value: Double?) {
        if let value { sqlite3_bind_double(stmt, index, value) }
        else { sqlite3_bind_null(stmt, index) }
    }

    private func bindOptionalBlob(_ stmt: OpaquePointer?, _ index: Int32, _ value: Data?) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        if value.isEmpty {
            sqlite3_bind_zeroblob(stmt, index, 0)
        } else {
            value.withUnsafeBytes { raw in
                sqlite3_bind_blob(stmt, index, raw.baseAddress, Int32(value.count), SQLITE_TRANSIENT)
            }
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL,
              let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func columnDouble(_ stmt: OpaquePointer?, _ index: Int32) -> Double? {
        guard sqlite3_column_type(stmt, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(stmt, index)
    }

    private func columnBlob(_ stmt: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(stmt, index) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(stmt, index) else { return nil }
        let count = Int(sqlite3_column_bytes(stmt, index))
        guard count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }
}
