// File: Features/IRIS/IRISChatView.swift
//
// Chat surface for IRIS. Rainbow gradient accent honors her namesake. Premium
// gating is applied at the navigation entry point in MoreView.

import SwiftUI

struct IRISChatView: View {

    /// Optional opening prompt — when set, IRIS sends it automatically on
    /// first appear. Used by IRISSuggestionCardView to pre-load a question.
    var initialPrompt: String? = nil

    @State private var vm = IRISChatViewModel()
    @StateObject private var voice = IRISVoiceController()
    @Environment(IRISActionRouter.self) private var router
    @State private var draft: String = ""
    @State private var didDispatchInitial = false
    @State private var isCommitting = false
    @State private var didWireVoice = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider().background(Color.white.opacity(0.08))
                if IRISAgentService.shared.isAvailable || MockDataService.isEnabled {
                    chatTranscript
                    if let pending = router.pendingAction {
                        IRISConfirmationCard(
                            action: pending,
                            isCommitting: isCommitting,
                            onConfirm: { confirmPending(pending) },
                            onCancel: { cancelPending() }
                        )
                    }
                    if voice.isActive || voice.statusMessage != nil {
                        voiceStatusStrip
                    }
                    inputBar
                } else {
                    unavailableState
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task {
            wireVoiceIfNeeded()
            guard !didDispatchInitial, let prompt = initialPrompt, !prompt.isEmpty else { return }
            didDispatchInitial = true
            await vm.send(prompt)
        }
        .onDisappear { voice.stop() }
        .toolbar {
            ToolbarItem(placement: .principal) { titleBadge }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { vm.clear() } label: {
                        Label("New conversation", systemImage: "arrow.clockwise")
                    }
                    NavigationLink {
                        IRISMemoryView()
                    } label: {
                        Label("What IRIS remembers", systemImage: "brain.head.profile")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Chat options")
            }
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(hex: "#0A0A1E"), Color(hex: "#1A1340"), Color(hex: "#0D1B2A")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Header

    private var titleBadge: some View {
        HStack(spacing: 6) {
            irisOrb
            Text("IRIS")
                .font(.system(.headline, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .tracking(2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INTELLIGENT ROUTING & ITINERARY SPECIALIST")
                .font(.system(size: 9, weight: .black))
                .tracking(1.5)
                .foregroundStyle(rainbowGradient)
            if vm.messages.isEmpty {
                Text(vm.greeting)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Transcript

    private var chatTranscript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { msg in
                        bubble(msg, showRating: true)
                            .id(msg.id)
                    }
                    if vm.isResponding && !vm.streamingContent.isEmpty {
                        bubble(IRISMessage(role: .assistant, content: vm.streamingContent))
                            .id("streaming")
                    } else if vm.isResponding {
                        thinkingIndicator.id("thinking")
                    }
                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .onChange(of: vm.messages.count) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: vm.streamingContent) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if vm.isResponding {
                proxy.scrollTo(vm.streamingContent.isEmpty ? "thinking" : "streaming", anchor: .bottom)
            } else if let last = vm.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func bubble(_ msg: IRISMessage, showRating: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if msg.role == .assistant {
                irisOrb
                    .padding(.top, 4)
            } else {
                Spacer(minLength: 40)
            }
            VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 4) {
                if msg.role == .assistant {
                    Text("IRIS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(1.3)
                        .foregroundStyle(rainbowGradient)
                }
                Text(msg.content)
                    .font(.body)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(msg.role == .user
                                  ? JetsetterTheme.Colors.accent.opacity(0.85)
                                  : Color.white.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                msg.role == .assistant ? Color.white.opacity(0.1) : .clear,
                                lineWidth: 0.5
                            )
                    )
                    .textSelection(.enabled)

                if showRating, msg.role == .assistant, !vm.ratedMessageIDs.contains(msg.id) {
                    ratingButtons(for: msg)
                }
            }
            if msg.role == .user { } else { Spacer(minLength: 40) }
        }
    }

    /// A quiet thumbs up/down under IRIS replies. Feeds the on-device metrics ledger
    /// (`profileLift`) so we can tell whether personalization is actually helping.
    private func ratingButtons(for msg: IRISMessage) -> some View {
        HStack(spacing: 18) {
            Button { vm.rateReply(msg, helpful: true) } label: {
                Image(systemName: "hand.thumbsup")
            }
            .accessibilityLabel("Helpful")
            Button { vm.rateReply(msg, helpful: false) } label: {
                Image(systemName: "hand.thumbsdown")
            }
            .accessibilityLabel("Not helpful")
        }
        .font(.caption)
        .buttonStyle(.plain)
        .foregroundStyle(.white.opacity(0.4))
        .padding(.top, 3)
        .padding(.leading, 2)
    }

    @State private var thinkingPulse = false

    private var thinkingIndicator: some View {
        HStack(spacing: 8) {
            irisOrb
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(0.6))
                        .frame(width: 6, height: 6)
                        // Staggered bounce: each dot animates the shared `thinkingPulse`
                        // flag with its own delay, repeating forever while visible.
                        .scaleEffect(thinkingPulse ? 1.0 : 0.4)
                        .opacity(thinkingPulse ? 1.0 : 0.4)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                            value: thinkingPulse
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            Spacer(minLength: 40)
        }
        .onAppear { thinkingPulse = true }
        .onDisappear { thinkingPulse = false }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { voice.toggle() } label: {
                Image(systemName: voice.isActive ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(voice.isActive
                                     ? AnyShapeStyle(Color(hex: "#E84040"))
                                     : AnyShapeStyle(rainbowGradient))
            }
            .accessibilityLabel(voice.isActive ? "Stop voice mode" : "Talk to IRIS")

            TextField("Ask IRIS anything…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
                .foregroundStyle(.white)
                .tint(JetsetterTheme.Colors.accent)
                .submitLabel(.send)
                .disabled(vm.isResponding)
                .onSubmit { if canSend { dispatchSend() } }

            Button { dispatchSend() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend
                                     ? AnyShapeStyle(rainbowGradient)
                                     : AnyShapeStyle(Color.white.opacity(0.25)))
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.8))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !vm.isResponding
    }

    private func dispatchSend() {
        let text = draft
        draft = ""
        Task { await vm.send(text) }
    }

    // MARK: - Voice

    private func wireVoiceIfNeeded() {
        guard !didWireVoice else { return }
        didWireVoice = true
        // Bridge a finalized spoken utterance into the chat and hand IRIS's
        // reply back so the controller can speak it, then resume listening. Uses the
        // non-streaming path (sendSpoken) — the voice loop only needs the final text.
        voice.onUtterance = { text in
            await vm.sendSpoken(text)
        }
    }

    private var voiceStatusStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: voiceIcon)
                .foregroundStyle(rainbowGradient)
            Text(voice.statusMessage ?? voiceStateLabel)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial.opacity(0.6))
        // Barge-in: tap while IRIS is speaking to cut her off and start listening.
        .contentShape(Rectangle())
        .onTapGesture {
            if voice.state == .speaking { voice.interruptSpeaking() }
        }
    }

    private var voiceStateLabel: String {
        switch voice.state {
        case .idle:      return "Tap the mic to talk to IRIS."
        case .listening: return voice.liveTranscript.isEmpty ? "Listening…" : voice.liveTranscript
        case .thinking:  return "Thinking…"
        case .speaking:  return "IRIS is speaking… (tap to interrupt)"
        }
    }

    private var voiceIcon: String {
        switch voice.state {
        case .idle:      return "mic"
        case .listening: return "waveform"
        case .thinking:  return "ellipsis"
        case .speaking:  return "speaker.wave.2.fill"
        }
    }

    // MARK: - Pending action confirmation

    private func confirmPending(_ action: IRISPendingAction) {
        guard !isCommitting else { return }
        isCommitting = true
        Task {
            let result = await action.commit()
            router.cancelPendingAction()
            vm.recordActionResult(result)
            isCommitting = false
        }
    }

    private func cancelPending() {
        router.cancelPendingAction()
        vm.recordActionResult("No problem — I won't make that change.")
    }

    // MARK: - Unavailable

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Spacer()
            irisOrb.scaleEffect(2.5).padding(.bottom, 12)
            Text("IRIS is resting")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(IRISAgentService.shared.unavailabilityReason ?? "Apple Intelligence is required to chat with IRIS.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - IRIS orb + rainbow

    private var irisOrb: some View {
        Circle()
            .fill(rainbowGradient)
            .frame(width: 22, height: 22)
            .overlay(
                Circle().strokeBorder(Color.white.opacity(0.4), lineWidth: 0.5)
            )
            .shadow(color: Color(hex: "#5A6BE0").opacity(0.5), radius: 4)
    }

    // A restrained, premium iridescent sweep (indigo → periwinkle → sky → teal)
    // rather than a full saturated rainbow. Keeps IRIS's "spectrum" identity while
    // reading confident and executive instead of consumer-playful. Name retained
    // to avoid churning the six call sites that reference it.
    private var rainbowGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(hex: "#6B5BE6"), // indigo
                Color(hex: "#4E8FE8"), // periwinkle
                Color(hex: "#3B9EF0"), // sky (app accent)
                Color(hex: "#2FBFB8")  // teal
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

#Preview {
    NavigationStack { IRISChatView() }
        .environment(IRISActionRouter.shared)
}
