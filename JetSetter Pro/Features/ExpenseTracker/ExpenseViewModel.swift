// File: Features/ExpenseTracker/ExpenseViewModel.swift

import Foundation
import SwiftUI
import CoreLocation
import MapKit

// MARK: - ExpenseViewModel

/// Manages all expense state — manual entry, OCR receipt scanning, mileage logging,
/// and persistence.
///
/// Expenses are FINANCIAL data, so they live only on-device in the encrypted SQLite
/// store (`FinancialStore`) and never sync to Supabase. The in-memory `expenses`
/// array is the UI's source of truth for the session; every mutation is mirrored to
/// SQLite, and `load()` reconciles from SQLite on appear.
@MainActor
@Observable
final class ExpenseViewModel {

    // MARK: - Published State

    var expenses: [Expense] = []
    var isProcessingOCR: Bool = false
    var ocrResult: OCRReceiptResult? = nil
    var errorMessage: String? = nil

    /// Category suggested by on-device Apple Intelligence after a receipt scan.
    /// `nil` when the model is unavailable or hasn't run — the UI should fall
    /// back to its own default in that case.
    private(set) var suggestedCategory: ExpenseCategory? = nil

    // MARK: - Store

    /// On-device, encrypted SQLite store (device-only; never synced).
    private let store: FinancialStore

    // MARK: - Init

    // `nonisolated(unsafe)` so the observer can be removed from the nonisolated
    // `deinit`. Safe: written once in `init`, read once in `deinit`, and
    // `NotificationCenter.removeObserver` is itself thread-safe. (Same pattern as
    // ItineraryViewModel.)
    nonisolated(unsafe) private var expensesChangedObserver: NSObjectProtocol?

    init(store: FinancialStore = .shared) {
        self.store = store
        // Expenses load asynchronously from SQLite via `load()`, invoked from the
        // view's `.task`. Kept out of `init` so it never blocks the main thread on
        // disk I/O and so previews/tests can construct the VM cheaply.
        //
        // Reload whenever ANY writer mutates the expense store out-of-band (Siri/App
        // Intents, IRIS, TravelStore, or another view-model), so our in-memory copy
        // never goes stale and a later write can't clobber their change.
        expensesChangedObserver = NotificationCenter.default.addObserver(
            forName: .jetSetterExpensesChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.load() }
        }
    }

    deinit {
        if let expensesChangedObserver {
            NotificationCenter.default.removeObserver(expensesChangedObserver)
        }
    }

    // MARK: - Computed Stats

    /// Per-currency subtotals — summing across mixed currencies produces a
    /// meaningless figure, so totals are grouped by each expense's currency.
    private(set) var totalsByCurrency: [String: Double] = [:]

    /// Human-readable per-currency total (e.g. "USD 120.00 · EUR 80.00").
    /// Returns "USD 0.00" when there are no expenses.
    var totalSummary: String {
        guard !totalsByCurrency.isEmpty else { return "USD 0.00" }
        return totalsByCurrency
            .sorted { $0.key < $1.key }
            .map { String(format: "%@ %.2f", $0.key, $0.value) }
            .joined(separator: " · ")
    }

    /// True when every expense shares a single currency — the category chart
    /// is only meaningful (comparable amounts on one axis) in that case.
    var hasSingleCurrency: Bool {
        totalsByCurrency.count <= 1
    }

    /// The shared currency code when `hasSingleCurrency`, else "USD".
    var displayCurrency: String {
        totalsByCurrency.count == 1 ? (totalsByCurrency.first?.key ?? "USD") : "USD"
    }

    /// Expenses grouped by category — updated only on mutations, not every render.
    private(set) var expensesByCategory: [ExpenseCategory: Double] = [:]

    /// Expenses sorted most-recent-first — cached as @Published so the List/ForEach
    /// only re-renders when the data actually changes, not on every parent body evaluation.
    private(set) var sortedExpenses: [Expense] = []

    private func updateDerivedState() {
        sortedExpenses = expenses.sorted { $0.date > $1.date }
        totalsByCurrency = Dictionary(grouping: expenses, by: \.currency)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
        expensesByCategory = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
    }

    // MARK: - Persistence

    /// Loads expenses from the on-device SQLite store. Invoked from the view's
    /// `.task`; safe to call repeatedly.
    func load() async {
        expenses = await store.allExpenses()
        updateDerivedState()
    }

    // MARK: - CRUD

    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        updateDerivedState()
        // GRANULAR persist: upsert just this row. Never re-write the whole table for a
        // single add — a DELETE-and-reinsert would wipe expenses inserted out-of-band by
        // Siri/IRIS/App Intents/TravelStore that this view-model never observed.
        Task { await store.upsert(expense) }
        // Learning: every expense is a spend signal; OCR-sourced ones are receipts.
        TravelProfileStore.shared.record(
            expense.receiptText != nil ? .receiptScanned : .expenseLogged,
            value: expense.merchant,
            attributes: [
                "category": expense.category.displayName,
                "amount": String(expense.amount),
                "currency": expense.currency
            ],
            source: "expenses"
        )
    }

    func deleteExpense(at offsets: IndexSet) {
        // Map offsets against sortedExpenses back to the main array
        let sorted = sortedExpenses
        var removedIDs: [UUID] = []
        offsets.forEach { index in
            let expenseToDelete = sorted[index]
            removedIDs.append(expenseToDelete.id)
            expenses.removeAll { $0.id == expenseToDelete.id }
        }
        updateDerivedState()
        // GRANULAR persist: delete only the affected rows, leaving every other row
        // (including out-of-band writes) intact.
        let ids = removedIDs
        Task { for id in ids { await store.delete(expenseID: id) } }
    }

    // MARK: - OCR Receipt Scan

    /// Sends the captured image to `VisionOCRService` (Google Cloud Vision text
    /// detection — the receipt image leaves the device) and stores the parsed
    /// result. Category classification is a separate on-device step. The result
    /// is presented for user confirmation before saving.
    func scanReceipt(image: UIImage) async {
        isProcessingOCR = true
        errorMessage = nil
        ocrResult = nil
        suggestedCategory = nil

        defer { isProcessingOCR = false }

        do {
            let result = try await VisionOCRService.shared.annotateReceipt(image: image)
            ocrResult = result
            // Classify on-device once OCR succeeds. Best-effort — leaves
            // suggestedCategory nil if Apple Intelligence is unavailable.
            suggestedCategory = await ExpenseCategorizer.shared.suggestCategory(
                merchant: result.extractedMerchant ?? "",
                receiptText: result.rawText
            )
        } catch let error as OCRError {
            errorMessage = error.errorDescription
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Receipt scan failed. You can enter the amount manually."
        }
    }

    /// Creates and saves an expense from a confirmed OCR result. The receipt's OCR
    /// text and (optionally) its captured image bytes are persisted alongside the
    /// expense in the encrypted, device-only SQLite store — receipt images never
    /// leave the device.
    func confirmOCRExpense(
        amount: Double,
        currency: String,
        merchant: String,
        category: ExpenseCategory,
        notes: String?,
        receiptImageData: Data? = nil
    ) {
        let rawText = ocrResult?.rawText
        let expense = Expense(
            amount: amount,
            currency: currency,
            category: category,
            merchant: merchant.isEmpty ? "Receipt" : merchant,
            notes: notes,
            receiptText: rawText
        )
        addExpense(expense)
        // Persist the receipt (OCR text + optional image bytes) device-only, AFTER the
        // parent expense row exists. The `receipts` FK (ON DELETE CASCADE, enforced via
        // `PRAGMA foreign_keys = ON`) rejects a receipt whose expense isn't present yet,
        // and `addExpense`'s upsert runs in its own unordered Task — so we re-`upsert`
        // the expense here (idempotent INSERT OR REPLACE) and then save the receipt in
        // the same ordered Task to guarantee the parent lands first.
        if rawText != nil || receiptImageData != nil {
            let receipt = Receipt(expenseID: expense.id, ocrText: rawText, imageData: receiptImageData)
            let parent = expense
            Task {
                await store.upsert(parent)
                await store.saveReceipt(receipt)
            }
        }
        ocrResult = nil
        suggestedCategory = nil
    }

    // MARK: - Manual Categorization

    /// True when on-device Apple Intelligence can suggest a category right now.
    var isCategorizationAvailable: Bool {
        ExpenseCategorizer.shared.isAvailable
    }

    /// On-demand category suggestion for manual entry. Returns nil when the
    /// on-device model is unavailable, leaving the caller's current pick intact.
    func categorize(merchant: String, notes: String?) async -> ExpenseCategory? {
        await ExpenseCategorizer.shared.suggestCategory(merchant: merchant, notes: notes)
    }

    // MARK: - Mileage Log

    /// Calculates the mileage reimbursement for a given distance and adds it as an expense.
    func logMileage(
        fromAddress: String,
        toAddress: String,
        distanceMiles: Double,
        notes: String?
    ) {
        let date = Date()
        let amount = Expense.mileageAmount(for: distanceMiles, on: date)
        let expense = Expense(
            amount: amount,
            category: .mileage,
            merchant: "\(fromAddress) → \(toAddress)",
            date: date,
            notes: notes,
            mileageDistance: distanceMiles
        )
        addExpense(expense)
    }

    /// Calculates the driving distance in miles between two addresses using MapKit directions.
    /// On failure returns `nil` and sets `errorMessage` with a reason that distinguishes the
    /// failure mode (unrecognized address vs. no driving route vs. offline/other), so the UI
    /// can surface feedback instead of the spinner silently vanishing.
    func calculateDistance(from origin: String, to destination: String) async -> Double? {
        errorMessage = nil
        do {
            let geocoder = CLGeocoder()
            async let originPlacemarks = geocoder.geocodeAddressString(origin)
            async let destinationPlacemarks = geocoder.geocodeAddressString(destination)

            let (origins, destinations) = try await (originPlacemarks, destinationPlacemarks)

            guard let originCoord = origins.first?.location?.coordinate,
                  let destCoord   = destinations.first?.location?.coordinate else {
                errorMessage = "Couldn't recognize one of those addresses. Please check and try again."
                return nil
            }

            let request = MKDirections.Request()
            request.source      = MKMapItem(placemark: MKPlacemark(coordinate: originCoord))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
            request.transportType = .automobile

            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else {
                errorMessage = "Couldn't find a driving route between those addresses."
                return nil
            }
            return route.distance / 1609.34  // meters → miles

        } catch {
            errorMessage = "Couldn't calculate the distance. Check your connection and the addresses, then try again."
            return nil
        }
    }
}
