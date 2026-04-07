// File: Features/Assistant/AssistantView.swift

import SwiftUI

// MARK: - AssistantView

/// Full-screen AI travel assistant chat interface.
/// The user types questions and Claude responds with travel guidance.
struct AssistantView: View {

    @StateObject private var viewModel = AssistantViewModel()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var errorDismissTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputBar
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !viewModel.messages.isEmpty {
                        Button("Clear") {
                            viewModel.clearConversation()
                        }
                        .foregroundStyle(JetsetterTheme.Colors.accent)
                    }
                }
            }
            // Dismiss error banner automatically; cancels any prior pending dismiss
            .onChange(of: viewModel.errorMessage) { _, newValue in
                errorDismissTask?.cancel()
                guard newValue != nil else { return }
                errorDismissTask = Task {
                    try? await Task.sleep(for: .seconds(4))
                    viewModel.errorMessage = nil
                }
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: JetsetterTheme.Spacing.small) {
                    // Empty state — shown before first message
                    if viewModel.messages.isEmpty {
                        emptyStateView
                    }

                    ForEach(viewModel.messages) { message in
                        ChatBubbleView(message: message)
                            .id(message.id)
                    }

                    // Typing indicator — shown while waiting for Claude
                    if viewModel.isWaitingForResponse {
                        TypingIndicatorView()
                            .id("typing")
                    }

                    // Error banner — shown inline when a request fails
                    if let error = viewModel.errorMessage {
                        errorBanner(message: error)
                            .id("error")
                    }
                }
                .padding(JetsetterTheme.Spacing.medium)
            }
            // Auto-scroll to latest message or typing indicator
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: scrollProxy)
            }
            .onChange(of: viewModel.isWaitingForResponse) { _, _ in
                scrollToBottom(proxy: scrollProxy)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: JetsetterTheme.Spacing.small) {
            TextField("Ask anything about your trip…", text: $inputText, axis: .vertical)
                .lineLimit(1...5)
                .padding(JetsetterTheme.Spacing.small)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(20)
                .focused($isInputFocused)

            // Send button — disabled while waiting or if input is empty
            Button {
                submitMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(
                        canSend
                            ? JetsetterTheme.Colors.accent
                            : Color.secondary.opacity(0.4)
                    )
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, JetsetterTheme.Spacing.medium)
        .padding(.vertical, JetsetterTheme.Spacing.small)
        .background(.background)
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: JetsetterTheme.Spacing.large) {
            Spacer(minLength: 60)

            Image(systemName: "sparkles")
                .font(.system(size: 52))
                .foregroundStyle(JetsetterTheme.Colors.accent.opacity(0.5))

            VStack(spacing: JetsetterTheme.Spacing.small) {
                Text("Your AI Travel Assistant")
                    .font(.headline)

                Text("Ask me anything — packing lists, visa requirements, the best time to visit, local tips, and more.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, JetsetterTheme.Spacing.large)
            }

            // Suggestion chips
            VStack(spacing: JetsetterTheme.Spacing.small) {
                suggestionChip("What should I pack for Tokyo in April?")
                suggestionChip("Do I need a visa for France?")
                suggestionChip("Best airports for layovers?")
            }

            Spacer(minLength: 20)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: JetsetterTheme.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(JetsetterTheme.Colors.danger)

            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(JetsetterTheme.Spacing.small)
        .background(JetsetterTheme.Colors.danger.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: - Suggestion Chip

    private func suggestionChip(_ text: String) -> some View {
        Button {
            inputText = text
            submitMessage()
        } label: {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(JetsetterTheme.Colors.accent)
                .padding(.horizontal, JetsetterTheme.Spacing.medium)
                .padding(.vertical, JetsetterTheme.Spacing.small)
                .background(JetsetterTheme.Colors.accent.opacity(0.1))
                .cornerRadius(20)
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isWaitingForResponse
    }

    private func submitMessage() {
        guard canSend else { return }
        let text = inputText
        inputText = ""
        Task { await viewModel.sendMessage(text) }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.25)) {
            if viewModel.isWaitingForResponse {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = viewModel.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - ChatBubbleView

/// Renders a single message bubble, aligned by role (user = right, assistant = left).
private struct ChatBubbleView: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .bottom, spacing: JetsetterTheme.Spacing.small) {
            if isUser { Spacer(minLength: 60) }

            // Assistant avatar icon
            if !isUser {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(JetsetterTheme.Colors.accent)
                    .clipShape(Circle())
            }

            Text(message.content)
                .font(.body)
                .foregroundStyle(isUser ? .white : .primary)
                .padding(.horizontal, JetsetterTheme.Spacing.medium)
                .padding(.vertical, JetsetterTheme.Spacing.small)
                .background(isUser ? JetsetterTheme.Colors.accent : Color(.secondarySystemBackground))
                .cornerRadius(18)
                // Flatten the bottom corner on the side the tail appears
                .clipShape(
                    isUser
                        ? RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomLeft])
                        : RoundedCornerShape(radius: 18, corners: [.topLeft, .topRight, .bottomRight])
                )
                .textSelection(.enabled)

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

// MARK: - TypingIndicatorView

/// Three animated dots shown while Claude is generating a response.
private struct TypingIndicatorView: View {
    @State private var animationOffset: [CGFloat] = [0, 0, 0]

    var body: some View {
        HStack(alignment: .bottom, spacing: JetsetterTheme.Spacing.small) {
            // Assistant avatar to match bubble layout
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(JetsetterTheme.Colors.accent)
                .clipShape(Circle())

            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .offset(y: animationOffset[index])
                        .onAppear {
                            // Stagger each dot's animation by 0.15 seconds
                            withAnimation(
                                .easeInOut(duration: 0.5)
                                .repeatForever()
                                .delay(Double(index) * 0.15)
                            ) {
                                animationOffset[index] = -6
                            }
                        }
                }
            }
            .padding(.horizontal, JetsetterTheme.Spacing.medium)
            .padding(.vertical, JetsetterTheme.Spacing.medium)
            .background(Color(.secondarySystemBackground))
            .cornerRadius(18)

            Spacer(minLength: 60)
        }
    }
}

// MARK: - RoundedCornerShape

/// Custom shape that rounds only specific corners — used to create chat bubble tails.
private struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Preview

#Preview("Empty State") {
    AssistantView()
}

#Preview("With Messages") {
    let view = AssistantView()
    return view
}
