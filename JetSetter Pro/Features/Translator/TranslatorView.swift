// File: Features/Translator/TranslatorView.swift
//
// Live translator powered by Apple's Translation framework. Source text can
// be typed or captured from the camera via VisionKit's DataScannerViewController.
// Everything runs on-device — no API keys.

import SwiftUI
import Translation
import VisionKit
import AVFoundation

struct TranslatorView: View {

    @State private var sourceText: String = ""
    @State private var translatedText: String = ""
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var targetLanguage: Locale.Language = .init(identifier: "ja")
    @State private var showLanguagePicker = false
    @State private var showCameraScanner = false
    @State private var isTranslating = false
    @State private var errorMessage: String?

    /// Common target languages travelers reach for. Real list comes from
    /// `LanguageAvailability.supportedLanguages` at runtime.
    private static let presetLanguages: [(label: String, flag: String, code: String)] = [
        ("Japanese", "🇯🇵", "ja"),
        ("French", "🇫🇷", "fr"),
        ("Spanish", "🇪🇸", "es"),
        ("Italian", "🇮🇹", "it"),
        ("German", "🇩🇪", "de"),
        ("Portuguese", "🇵🇹", "pt"),
        ("Chinese (Simplified)", "🇨🇳", "zh-Hans"),
        ("Chinese (Traditional)", "🇹🇼", "zh-Hant"),
        ("Korean", "🇰🇷", "ko"),
        ("Thai", "🇹🇭", "th"),
        ("Vietnamese", "🇻🇳", "vi"),
        ("Arabic", "🇸🇦", "ar"),
        ("Hindi", "🇮🇳", "hi"),
        ("Turkish", "🇹🇷", "tr"),
        ("Dutch", "🇳🇱", "nl"),
        ("Greek", "🇬🇷", "el"),
        ("Russian", "🇷🇺", "ru"),
        ("Hebrew", "🇮🇱", "he"),
        ("Indonesian", "🇮🇩", "id"),
        ("English", "🇺🇸", "en")
    ]

    /// Normalizes a `Locale.Language` to a preset code for equality checks.
    /// `maximalIdentifier` yields values like "ja-Jpan-JP" that never match the
    /// short preset codes ("ja", "fr"), so compare on the base language code and
    /// special-case the script-differentiated Chinese variants ("zh-Hans"/"zh-Hant").
    private static func presetCode(for language: Locale.Language) -> String {
        let base = language.languageCode?.identifier ?? language.minimalIdentifier
        if base == "zh" {
            switch language.script?.identifier {
            case "Hant": return "zh-Hant"
            default: return "zh-Hans"
            }
        }
        return base
    }

    private var currentLanguageDisplay: (label: String, flag: String) {
        let code = Self.presetCode(for: targetLanguage)
        if let match = Self.presetLanguages.first(where: { $0.code == code }) {
            return (match.label, match.flag)
        }
        return ("Target", "🌐")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                languagePickerButton
                sourceCard
                arrowDivider
                translatedCard
                actionButtons
                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(16)
        }
        .background(JetsetterTheme.Colors.background)
        .navigationTitle("Translator")
        .navigationBarTitleDisplayMode(.large)
        .translationTask(translationConfig) { session in
            await runTranslation(with: session)
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerSheet(
                presets: Self.presetLanguages,
                selectedCode: Self.presetCode(for: targetLanguage),
                onSelect: { code in
                    targetLanguage = .init(identifier: code)
                    triggerTranslation()
                }
            )
        }
        .fullScreenCover(isPresented: $showCameraScanner) {
            ZStack(alignment: .top) {
                CameraTextScanner(
                    onScan: { text in
                        sourceText = text
                        showCameraScanner = false
                        triggerTranslation()
                    }
                )
                .ignoresSafeArea()

                // Overlay controls — the scanner itself is a bare camera feed, so
                // this bar is the only way to leave without tapping a text item.
                HStack {
                    Button { showCameraScanner = false } label: {
                        Text("Cancel")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.55), in: Capsule())
                    }
                    Spacer()
                    Label("Tap any text to capture", systemImage: "text.viewfinder")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    // MARK: - Sections

    private var languagePickerButton: some View {
        Button { showLanguagePicker = true } label: {
            HStack(spacing: 10) {
                Text(currentLanguageDisplay.flag)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TRANSLATE INTO")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.5)
                        .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    Text(currentLanguageDisplay.label)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption.bold())
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .jetCard()
        }
        .buttonStyle(.plain)
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SOURCE")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(JetsetterTheme.Colors.accent)
                Spacer()
                if !sourceText.isEmpty {
                    Button {
                        sourceText = ""
                        translatedText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
            }
            TextField("Type text here, or scan with the camera", text: $sourceText, axis: .vertical)
                .lineLimit(3...8)
                .font(.body)
        }
        .padding(14)
        .jetCard()
    }

    private var translatedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRANSLATION")
                    .font(JetsetterTheme.Typography.label)
                    .tracking(1.5)
                    .foregroundStyle(JetsetterTheme.Colors.success)
                Spacer()
                if isTranslating {
                    ProgressView().scaleEffect(0.8)
                } else if !translatedText.isEmpty {
                    Button {
                        UIPasteboard.general.string = translatedText
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(JetsetterTheme.Colors.textSecondary)
                    }
                }
            }
            if translatedText.isEmpty {
                Text("Translation appears here")
                    .font(.body)
                    .foregroundStyle(JetsetterTheme.Colors.textSecondary.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            } else {
                Text(translatedText)
                    .font(.body)
                    .foregroundStyle(JetsetterTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
            }
        }
        .padding(14)
        .jetCard()
    }

    private var arrowDivider: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.title2)
            .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.5))
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                Button { showCameraScanner = true } label: {
                    Label("Scan with Camera", systemImage: "camera.fill")
                        .font(.subheadline.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(JetsetterTheme.Colors.accent)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            Button { triggerTranslation() } label: {
                Label("Translate", systemImage: "globe")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(sourceText.isEmpty ? Color(.systemFill) : JetsetterTheme.Colors.success)
                    .foregroundStyle(sourceText.isEmpty ? Color.secondary : Color.white)
                    .clipShape(Capsule())
            }
            .disabled(sourceText.isEmpty)
        }
    }

    // MARK: - Translation

    private func triggerTranslation() {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        translatedText = ""
        errorMessage = nil
        isTranslating = true
        // `.translationTask` only re-fires when the Configuration value changes.
        // Re-translating the same source→target yields an equal Configuration, so
        // the closure would never run again and the ProgressView would spin forever.
        // If a config already exists for the current target, invalidate it to force
        // the task to re-run; otherwise (first run, or the target language changed)
        // assign a fresh Configuration for the current target language.
        if var existing = translationConfig, existing.target == targetLanguage {
            // Same target as last time → an identical Configuration wouldn't
            // re-fire .translationTask. invalidate() bumps the config's internal
            // `version`, making the reassigned value compare unequal so the task
            // re-runs. It's a mutating call, and @State's setter can't provide
            // inout access, so mutate a local copy and assign it back.
            existing.invalidate()
            translationConfig = existing
        } else {
            translationConfig = TranslationSession.Configuration(source: nil, target: targetLanguage)
        }
    }

    private func runTranslation(with session: TranslationSession) async {
        defer { isTranslating = false }
        do {
            let response = try await session.translate(sourceText)
            await MainActor.run {
                translatedText = response.targetText
            }
        } catch {
            await MainActor.run {
                errorMessage = "Couldn't translate: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Language picker sheet

private struct LanguagePickerSheet: View {
    let presets: [(label: String, flag: String, code: String)]
    let selectedCode: String
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [(label: String, flag: String, code: String)] {
        if search.isEmpty { return presets }
        return presets.filter { $0.label.lowercased().contains(search.lowercased()) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.code) { item in
                Button {
                    onSelect(item.code)
                    dismiss()
                } label: {
                    HStack {
                        Text(item.flag).font(.title2)
                        Text(item.label).foregroundStyle(.primary)
                        Spacer()
                        if item.code == selectedCode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(JetsetterTheme.Colors.accent)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search languages")
            .navigationTitle("Target Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Camera Text Scanner

/// Wraps VisionKit's DataScannerViewController to capture live text from the
/// camera. Auto-completes when the user taps a recognized text item.
private struct CameraTextScanner: UIViewControllerRepresentable {

    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: CameraTextScanner
        init(parent: CameraTextScanner) { self.parent = parent }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case let .text(text) = item {
                parent.onScan(text.transcript)
            }
        }
    }
}
