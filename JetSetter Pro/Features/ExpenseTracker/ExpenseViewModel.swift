// File: Features/ExpenseTracker/ExpenseViewModel.swift

import Foundation
import Combine
import SwiftUI
import CoreLocation

// MARK: - ExpenseViewModel

/// Manages all expense state — manual entry, OCR receipt scanning, mileage logging,
/// and UserDefaults persistence.
/// TODO: Replace UserDefaults persistence with Supabase when backend is integrated.
@MainActor
final class ExpenseViewModel: ObservableObject {

    // MARK: - Published State

    @Published var expenses: [Expense] = []
    @Published var isProcessingOCR: Bool = false
    @Published var ocrResult: OCRReceiptResult? = nil
    @Published var errorMessage: String? = nil

    // MARK: - UserDefaults Key

    private let storageKey = "jetsetter_expenses"

    // MARK: - Init

    init() {
        loadExpenses()
    }

    // MARK: - Computed Stats

    /// Total amount of all expenses
    var totalAmount: Double {
        expenses.reduce(0) { $0 + $1.amount }
    }

    /// Expenses grouped by category — cached and updated only on mutations,
    /// not recomputed on every view render.
    @Published private(set) var expensesByCategory: [ExpenseCategory: Double] = [:]

    /// Most recent expenses first
    var sortedExpenses: [Expense] {
        expenses.sorted { $0.date > $1.date }
    }

    private func updateCategoryCache() {
        expensesByCategory = Dictionary(grouping: expenses, by: \.category)
            .mapValues { $0.reduce(0) { $0 + $1.amount } }
    }

    // MARK: - Persistence

    private func loadExpenses() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            expenses = try JSONDecoder().decode([Expense].self, from: data)
        } catch {
            expenses = []
        }
        updateCategoryCache()
    }

    private func saveExpenses() {
        do {
            let data = try JSONEncoder().encode(expenses)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            errorMessage = "Failed to save expenses."
        }
        updateCategoryCache()
    }

    // MARK: - CRUD

    func addExpense(_ expense: Expense) {
        expenses.append(expense)
        saveExpenses()
    }

    func deleteExpense(at offsets: IndexSet) {
        // Map offsets against sortedExpenses back to the main array
        let sorted = sortedExpenses
        offsets.forEach { index in
            let expenseToDelete = sorted[index]
            expenses.removeAll { $0.id == expenseToDelete.id }
        }
        saveExpenses()
    }

    // MARK: - OCR Receipt Scan

    /// Sends the captured image to Google Vision OCR and stores the parsed result.
    /// The result is presented for user confirmation before saving.
    func scanReceipt(image: UIImage) async {
        isProcessingOCR = true
        errorMessage = nil
        ocrResult = nil

        defer { isProcessingOCR = false }

        do {
            ocrResult = try await VisionOCRService.shared.annotateReceipt(image: image)
        } catch let error as OCRError {
            errorMessage = error.errorDescription
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Receipt scan failed. You can enter the amount manually."
        }
    }

    /// Creates and saves an expense from a confirmed OCR result.
    func confirmOCRExpense(
        amount: Double,
        merchant: String,
        category: ExpenseCategory,
        notes: String?
    ) {
        let expense = Expense(
            amount: amount,
            category: category,
            merchant: merchant.isEmpty ? "Receipt" : merchant,
            notes: notes,
            receiptText: ocrResult?.rawText
        )
        addExpense(expense)
        ocrResult = nil
    }

    // MARK: - Mileage Log

    /// Calculates the mileage reimbursement for a given distance and adds it as an expense.
    func logMileage(
        fromAddress: String,
        toAddress: String,
        distanceMiles: Double,
        notes: String?
    ) {
        let amount = Expense.mileageAmount(for: distanceMiles)
        let expense = Expense(
            amount: amount,
            category: .mileage,
            merchant: "\(fromAddress) → \(toAddress)",
            notes: notes,
            mileageDistance: distanceMiles
        )
        addExpense(expense)
    }

    /// Calculates the driving distance in miles between two addresses using CoreLocation geocoding.
    func calculateDistance(from origin: String, to destination: String) async -> Double? {
        do {
            let geocoder = CLGeocoder()
            async let originPlacemarks = geocoder.geocodeAddressString(origin)
            async let destinationPlacemarks = geocoder.geocodeAddressString(destination)

            let (origins, destinations) = try await (originPlacemarks, destinationPlacemarks)

            guard let originLocation = origins.first?.location,
                  let destinationLocation = destinations.first?.location else { return nil }

            // Straight-line distance in miles (driving distance would require MapKit directions)
            let meters = originLocation.distance(from: destinationLocation)
            return meters / 1609.34

        } catch {
            return nil
        }
    }
}
