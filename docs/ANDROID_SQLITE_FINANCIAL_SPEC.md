# Android Spec — On-Device SQLite Store for Financial Data

**Status:** spec (no Android code in this repo yet). This is the Android counterpart
to the iOS implementation in `JetSetter Pro/Core/Services/Financial/`
(`FinancialDatabase.swift`, `FinancialStore.swift`). Keep the two in lock-step.

## 0. The rule

**Financial data is device-only and NEVER leaves the device.** That means:

- **Expenses** (the `jetsetter_expenses` collection),
- **Currency-tracker expenses** (per-trip `jetsetter_currency_expenses_<tripId>`), and
- **Receipts** — OCR text and captured images.

These are stored **only** in a local, **encrypted** SQLite database (Room + SQLCipher).
They are never sent to Supabase, Firebase, analytics, or any third-party API, never
included in cloud/auto backup, and are wiped on account deletion and "Clear Local Data".

Everything else (trips, wallet passes, packing lists, disruption events, loyalty,
travel signals) is out of scope for this store and keeps its existing behavior.

## 1. Dependencies

```kotlin
// build.gradle (app)
dependencies {
    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")          // suspend DAO + Flow
    ksp("androidx.room:room-compiler:2.6.1")

    // Encryption at rest (parity with iOS FileProtectionType.complete).
    implementation("net.zetetic:sqlcipher-android:4.6.1")
    implementation("androidx.sqlite:sqlite:2.4.0")

    // Store the SQLCipher passphrase in an OS-protected location.
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
}
```

Room is the required approach (no raw SQLite boilerplate); SQLCipher provides the
encryption Room's default engine lacks. Jetpack Security (`EncryptedSharedPreferences`,
Android Keystore-backed) holds the DB passphrase — not the data itself.

## 2. Entities

Mirror the iOS models 1:1 (same fields, same category raw values). Store dates as epoch
**seconds** (`Double`/`REAL`) to match the iOS columns exactly, so an exported/imported
DB is byte-compatible across platforms.

```kotlin
@Entity(tableName = "expenses")
data class ExpenseEntity(
    @PrimaryKey val id: String,          // UUID string
    val amount: Double,
    val currency: String,                // ISO 4217, e.g. "USD"
    val category: String,                // ExpenseCategory name: FOOD, TRANSPORT, … (UPPERCASE)
    val merchant: String,
    val date: Double,                    // epoch seconds
    val notes: String?,
    val receiptText: String?,
    val mileageDistance: Double?,        // only set for MILEAGE
)

@Entity(
    tableName = "currency_expenses",
    indices = [Index("trip_id")],
)
data class CurrencyExpenseEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "trip_id") val tripId: String,
    val amount: Double,                  // destination currency
    val currency: String,                // destination currency code
    @ColumnInfo(name = "converted_amount") val convertedAmount: Double?, // home currency
    @ColumnInfo(name = "home_currency") val homeCurrency: String,
    val category: String,                // SpendCategory name: Food, Transport, … (matches iOS raw values)
    val description: String,
    val date: Double,
    @ColumnInfo(name = "receipt_image_path") val receiptImagePath: String?,
)

@Entity(
    tableName = "receipts",
    indices = [Index("expense_id")],
)
data class ReceiptEntity(
    @PrimaryKey val id: String,
    @ColumnInfo(name = "expense_id") val expenseId: String,
    @ColumnInfo(name = "ocr_text") val ocrText: String?,
    @ColumnInfo(name = "image_data", typeAffinity = ColumnInfo.BLOB) val imageData: ByteArray?,
    @ColumnInfo(name = "created_at") val createdAt: Double,
)
```

> `ExpenseCategory` raw values are UPPERCASE (`FOOD`, `TRANSPORT`, …) — the same
> cross-platform wire contract iOS uses (see `ExpenseModel.swift`). `SpendCategory`
> raw values are title-case (`Food`, `Transport`, …) to match `CurrencyModel.swift`.
> Keep both enums identical to iOS so a category never mismaps.

## 3. DAO

Mirrors the iOS store surface (`FinancialDatabase` / `FinancialStore`). Suspend
functions so all DB work is off the main thread — the Room equivalent of the iOS
`actor`/serial-queue.

```kotlin
@Dao
interface FinancialDao {
    // Expenses
    @Query("SELECT * FROM expenses") suspend fun allExpenses(): List<ExpenseEntity>
    @Upsert suspend fun upsertExpense(e: ExpenseEntity)
    @Query("DELETE FROM expenses WHERE id = :id") suspend fun deleteExpense(id: String)
    @Query("DELETE FROM expenses") suspend fun deleteAllExpenses()
    @Transaction suspend fun replaceAllExpenses(items: List<ExpenseEntity>) {
        deleteAllExpenses(); items.forEach { upsertExpense(it) }
    }

    // Currency expenses
    @Query("SELECT * FROM currency_expenses WHERE trip_id = :tripId")
    suspend fun currencyExpenses(tripId: String): List<CurrencyExpenseEntity>
    @Upsert suspend fun upsertCurrencyExpense(e: CurrencyExpenseEntity)
    @Query("DELETE FROM currency_expenses WHERE id = :id") suspend fun deleteCurrencyExpense(id: String)
    @Query("DELETE FROM currency_expenses WHERE trip_id = :tripId") suspend fun deleteCurrencyExpenses(tripId: String)
    @Transaction suspend fun replaceCurrencyExpenses(tripId: String, items: List<CurrencyExpenseEntity>) {
        deleteCurrencyExpenses(tripId); items.forEach { upsertCurrencyExpense(it) }
    }

    // Receipts
    @Upsert suspend fun upsertReceipt(r: ReceiptEntity)
    @Query("SELECT * FROM receipts WHERE expense_id = :expenseId ORDER BY created_at DESC LIMIT 1")
    suspend fun receiptForExpense(expenseId: String): ReceiptEntity?

    // Account deletion / clear
    @Transaction suspend fun wipeAll() {
        deleteAllExpenses()
        _wipeCurrency(); _wipeReceipts()
    }
    @Query("DELETE FROM currency_expenses") suspend fun _wipeCurrency()
    @Query("DELETE FROM receipts") suspend fun _wipeReceipts()
}
```

Expose a thin `FinancialStore` (repository) over the DAO — the parity of iOS's
`FinancialStore` actor — so view-models depend on a small, testable surface.

## 4. Encrypted database (parity with `FileProtectionType.complete`)

```kotlin
@Database(
    entities = [ExpenseEntity::class, CurrencyExpenseEntity::class, ReceiptEntity::class],
    version = 1,
    exportSchema = true,
)
abstract class FinancialDatabaseRoom : RoomDatabase() {
    abstract fun dao(): FinancialDao

    companion object {
        fun build(context: Context): FinancialDatabaseRoom {
            // Passphrase lives in Keystore-backed EncryptedSharedPreferences, generated once.
            val passphrase: ByteArray = FinancialDbKey.getOrCreate(context)
            val factory = SupportOpenHelperFactory(passphrase)   // net.zetetic:sqlcipher-android
            return Room.databaseBuilder(
                context,
                FinancialDatabaseRoom::class.java,
                // Keep it in internal storage (app-private, never on shared/external storage).
                context.getDatabasePath("financial.db").absolutePath,
            )
                .openHelperFactory(factory)   // <-- SQLCipher: encrypted at rest
                .build()
        }
    }
}
```

- **Encryption:** SQLCipher (AES-256). The passphrase is generated with a `SecureRandom`
  the first time, then stored in `EncryptedSharedPreferences` (Android Keystore master
  key). This is the closest Android analog to iOS's `FileProtectionType.complete`
  (file encrypted, unreadable while the device is locked / for other apps).
  *Alternative:* if SQLCipher can't be added, use Jetpack Security + a manually
  key-wrapped DB, but SQLCipher is preferred for whole-DB encryption.
- **Device-only / no backup:** exclude the DB from Auto Backup and Device-to-Device
  transfer so the encrypted file (and its key) can never leave the device:

  ```xml
  <!-- AndroidManifest.xml -->
  <application
      android:fullBackupContent="@xml/backup_rules"
      android:dataExtractionRules="@xml/data_extraction_rules" ... />
  ```
  ```xml
  <!-- res/xml/data_extraction_rules.xml -->
  <data-extraction-rules>
      <cloud-backup>
          <exclude domain="database" path="financial.db"/>
      </cloud-backup>
      <device-transfer>
          <exclude domain="database" path="financial.db"/>
      </device-transfer>
  </data-extraction-rules>
  ```
  (Mirror the same excludes in `backup_rules.xml` for API < 31.)

## 5. First-launch migration (SharedPreferences → Room)

Parity with iOS `migrateFromUserDefaultsIfNeeded()`. Run once, guarded by a flag, then
**delete the legacy keys so financial data is never written to SharedPreferences again.**

```kotlin
suspend fun migrateIfNeeded(prefs: SharedPreferences, dao: FinancialDao, json: Json) {
    if (prefs.getBoolean("jetsetter_financial_sqlite_migrated_v1", false)) return

    // 1. Expenses — legacy key "jetsetter_expenses" (JSON array of Expense).
    prefs.getString("jetsetter_expenses", null)?.let { raw ->
        runCatching { json.decodeFromString<List<Expense>>(raw) }.getOrDefault(emptyList())
            .map { it.toEntity() }
            .let { if (it.isNotEmpty()) dao.replaceAllExpenses(it) }
    }

    // 2. Currency expenses — one key per trip: "jetsetter_currency_expenses_<tripId>".
    prefs.all.keys
        .filter { it.startsWith("jetsetter_currency_expenses_") }
        .forEach { key ->
            (prefs.getString(key, null) ?: return@forEach).let { raw ->
                runCatching { json.decodeFromString<List<CurrencyExpense>>(raw) }
                    .getOrDefault(emptyList())
                    .map { it.toEntity() }
                    .forEach { dao.upsertCurrencyExpense(it) }
            }
        }

    // 3. Stop persisting financial data in SharedPreferences from here on.
    prefs.edit {
        remove("jetsetter_expenses")
        prefs.all.keys
            .filter { it.startsWith("jetsetter_currency_expenses_") }
            .forEach { remove(it) }
        putBoolean("jetsetter_financial_sqlite_migrated_v1", true)
    }
}
```

Notes:
- Be **tolerant** on decode (like iOS): historically these blobs may have used slightly
  different date encodings; try the strict decoder, fall back, and drop nothing you can
  parse.
- Migration is **idempotent** — the flag short-circuits repeat runs, and the source keys
  are gone after the first pass.

## 6. Wiring the view-models

- The expense and currency-tracker view-models read/write **only** through
  `FinancialStore` (repository over `FinancialDao`). No expense data goes through the
  Supabase/Retrofit layer.
- After OCR confirmation, persist the receipt's **OCR text and JPEG-compressed image
  bytes** into the `receipts` table linked to the new expense id (parity with the iOS
  `confirmOCRExpense(..., receiptImageData:)` path).
- **Account deletion** (App Store / Play equivalent) and **Clear Local Data** call
  `FinancialStore.wipeAll()` in addition to clearing SharedPreferences, so nothing
  lingers on-device.
- The account-deletion / cloud-sync code path must have **no expense table** — the
  Supabase backend has no `expenses` table (see `SETUP-SUPABASE.md §3`). Only trips
  (and the existing device-local collections) sync.

## 7. Tests (parity with `JetSetter ProTests/FinancialStoreTests.swift`)

Use an in-memory Room DB (`Room.inMemoryDatabaseBuilder`) for unit tests:

1. Expense CRUD — insert, read-back all fields, upsert-replaces-same-id, delete,
   `replaceAllExpenses` swaps the whole set, mileage fields preserved.
2. Currency-expense CRUD — scoped by `tripId`, full round-trip, `replaceCurrencyExpenses`
   only affects one trip.
3. Receipt round-trip — OCR text + image `ByteArray` in and out; absent image → null.
4. `wipeAll` clears every table.
5. **Migration round-trip** — seed a fake `SharedPreferences` with legacy
   `jetsetter_expenses` and a `jetsetter_currency_expenses_<tripId>` blob, run
   `migrateIfNeeded`, assert the rows landed in Room, the legacy keys were removed, and
   the flag is set; assert a second run is a no-op.

## 8. Parity checklist with iOS

| Concern | iOS | Android |
|---|---|---|
| Engine | `FinancialDatabase` (SQLite3 C, serial queue) | Room + SQLCipher |
| Async facade | `actor FinancialStore` | `FinancialStore` repo (suspend/coroutines) |
| Encryption at rest | `FileProtectionType.complete` | SQLCipher (AES-256) + Keystore key |
| No backup | excluded-from-backup + complete protection | Auto Backup / device-transfer excludes |
| Location | `Application Support/Financial/financial.sqlite` | app-internal `databases/financial.db` |
| Migration flag | `jetsetter_financial_sqlite_migrated_v1` | same key in `SharedPreferences` |
| Legacy expense key | `jetsetter_expenses` | same |
| Legacy currency key | `jetsetter_currency_expenses_<tripId>` | same |
| Receipts | `receipts` table (ocr_text + image BLOB) | `receipts` entity (ocrText + ByteArray) |
| Cloud sync of financial data | none (removed from `SupabaseService`) | none |
