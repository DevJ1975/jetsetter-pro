// File: Features/ExpenseTracker/ScanReceiptView.swift

import SwiftUI
import PhotosUI

// MARK: - ScanReceiptView

/// Sheet that lets the user take or select a receipt photo, runs OCR,
/// and presents the parsed result for confirmation before saving.
struct ScanReceiptView: View {

    @ObservedObject var viewModel: ExpenseViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Photo Selection State

    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var capturedImage: UIImage? = nil
    @State private var isShowingCamera: Bool = false

    // MARK: - Confirmation Form State

    @State private var confirmedAmount: String = ""
    @State private var confirmedMerchant: String = ""
    @State private var selectedCategory: ExpenseCategory = .other
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isProcessingOCR {
                    ocrLoadingView
                } else if viewModel.ocrResult != nil {
                    confirmationForm
                } else {
                    captureView
                }
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.ocrResult = nil
                        dismiss()
                    }
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                }
            }
            // When a photo is selected from library, run OCR
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task {
                    guard let newItem,
                          let data = try? await newItem.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return }
                    capturedImage = image
                    await viewModel.scanReceipt(image: image)
                    prefillForm()
                }
            }
            .sheet(isPresented: $isShowingCamera) {
                CameraPickerView { image in
                    capturedImage = image
                    Task {
                        await viewModel.scanReceipt(image: image)
                        prefillForm()
                    }
                }
            }
        }
    }

    // MARK: - Capture View (initial state)

    private var captureView: some View {
        VStack(spacing: JetsetterTheme.Spacing.xlarge) {
            Spacer()

            Image(systemName: "receipt")
                .font(.system(size: 64))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.5))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("Scan a Receipt")
                    .font(.headline)
                Text("Take a photo or choose one from your library. The amount and merchant will be extracted automatically.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(JetsetterTheme.Colors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
            }

            VStack(spacing: JetsetterTheme.Spacing.small) {
                // Camera button
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(JetsetterTheme.Spacing.medium)
                        .background(JetsetterTheme.Colors.accent)
                        .cornerRadius(14)
                }

                // Photo library picker
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose from Library", systemImage: "photo.on.rectangle")
                        .fontWeight(.semibold)
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                        .frame(maxWidth: .infinity)
                        .padding(JetsetterTheme.Spacing.medium)
                        .background(JetsetterTheme.Colors.accent.opacity(0.1))
                        .cornerRadius(14)
                }
            }
            .padding(.horizontal, JetsetterTheme.Spacing.large)

            Spacer()
        }
    }

    // MARK: - OCR Loading View

    private var ocrLoadingView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer()
            ProgressView().scaleEffect(1.6)
            Text("Reading receipt…")
                .font(.headline)
            Text("Extracting amount and merchant details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Confirmation Form

    private var confirmationForm: some View {
        Form {
            // Receipt thumbnail (if image captured)
            if let image = capturedImage {
                Section {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .cornerRadius(10)
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }
            }

            Section("Amount") {
                HStack {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("0.00", text: $confirmedAmount)
                        .keyboardType(.decimalPad)
                }
            }

            Section("Merchant") {
                TextField("Merchant name", text: $confirmedMerchant)
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategory) {
                    ForEach(ExpenseCategory.allCases.filter { $0 != .mileage }) { category in
                        Label(category.displayName, systemImage: category.systemImage)
                            .tag(category)
                    }
                }
            }

            Section("Notes (optional)") {
                TextField("Add a note…", text: $notes)
            }

            Section {
                Button {
                    saveExpense()
                } label: {
                    Text("Save Expense")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .listRowBackground(JetsetterTheme.Colors.accent)
                .disabled(confirmedAmount.isEmpty)
            }
        }
    }

    // MARK: - Helpers

    private func prefillForm() {
        guard let result = viewModel.ocrResult else { return }
        if let amount = result.extractedAmount {
            confirmedAmount = String(format: "%.2f", amount)
        }
        confirmedMerchant = result.extractedMerchant ?? ""
        // Auto-select category based on merchant name heuristics
        selectedCategory = guessCategory(from: confirmedMerchant)
    }

    private func guessCategory(from merchant: String) -> ExpenseCategory {
        let lower = merchant.lowercased()
        if lower.contains("hotel") || lower.contains("inn") || lower.contains("hyatt") || lower.contains("marriott") {
            return .accommodation
        }
        if lower.contains("restaurant") || lower.contains("café") || lower.contains("coffee") || lower.contains("starbucks") {
            return .food
        }
        if lower.contains("uber") || lower.contains("lyft") || lower.contains("taxi") || lower.contains("metro") {
            return .transport
        }
        return .other
    }

    private func saveExpense() {
        guard let amount = Double(confirmedAmount) else { return }
        viewModel.confirmOCRExpense(
            amount: amount,
            merchant: confirmedMerchant,
            category: selectedCategory,
            notes: notes.isEmpty ? nil : notes
        )
        dismiss()
    }
}

// MARK: - CameraPickerView

/// UIViewControllerRepresentable wrapping UIImagePickerController for camera capture.
/// UIKit bridge is required here as SwiftUI has no native camera API.
struct CameraPickerView: UIViewControllerRepresentable {

    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Preview

#Preview {
    ScanReceiptView(viewModel: ExpenseViewModel())
}
