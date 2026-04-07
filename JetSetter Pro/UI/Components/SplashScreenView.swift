// SplashScreenView.swift

import SwiftUI

struct SplashScreenView: View {
    @Binding var isVisible: Bool

    @State private var showIcon = false
    @State private var planeProgress: CGFloat = 0
    @State private var showSubtitle = false
    @State private var viewOpacity: Double = 1.0

    private let bgColor = Color(hex: "#10131E")
    private let goldColor = Color(hex: "#C9A84C")

    var body: some View {
        GeometryReader { geo in
            let sw = geo.size.width
            let sh = geo.size.height
            // Plane travels from 80pt off-screen left to 80pt off-screen right
            let planeX = -80 + planeProgress * (sw + 160)
            // Reveal mask: a rectangle that grows leftward from the leading edge
            // trails 50pt behind the plane center so the plane "draws" the text
            let revealWidth = max(0, planeX - 50)
            // Plane alpha: quick fade-in at entry, quick fade-out at exit
            let planeAlpha = min(1.0, min(planeProgress * 30, (1.0 - planeProgress) * 30))

            ZStack {
                // Dark navy background
                bgColor.ignoresSafeArea()

                // Subtle radial gold glow centered on screen
                RadialGradient(
                    colors: [goldColor.opacity(0.12), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: sw * 0.85
                )
                .ignoresSafeArea()

                // Main content column
                VStack(spacing: 20) {
                    Spacer()

                    // Circular icon badge with drop-in spring animation
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [goldColor.opacity(0.25), goldColor.opacity(0.05)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 45
                                )
                            )
                            .frame(width: 90, height: 90)
                            .overlay(Circle().stroke(goldColor.opacity(0.35), lineWidth: 1))

                        Image(systemName: "airplane")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(goldColor)
                            .rotationEffect(.degrees(-45))
                    }
                    .scaleEffect(showIcon ? 1.0 : 0.2)
                    .opacity(showIcon ? 1.0 : 0.0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.62), value: showIcon)

                    // "JetSetter Pro" wordmark — revealed by a growing mask as the plane crosses
                    // The text view is full-width so the mask coordinate space equals screen space (x=0 is left edge)
                    Text("JetSetter Pro")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [goldColor, goldColor.opacity(0.88), Color(hex: "#E8D5A3")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(maxWidth: .infinity, alignment: .center)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle().frame(width: revealWidth)
                                Spacer()
                            }
                        )

                    // Subtitle fades in after the plane exits
                    Text("YOUR EXECUTIVE TRAVEL COMPANION")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(3.5)
                        .foregroundStyle(Color(hex: "#8B92A8"))
                        .opacity(showSubtitle ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.7), value: showSubtitle)

                    Spacer()

                    Text("EST. 2025")
                        .font(.system(size: 10, weight: .light))
                        .tracking(5)
                        .foregroundStyle(goldColor.opacity(0.45))
                        .opacity(showSubtitle ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.7).delay(0.25), value: showSubtitle)
                        .padding(.bottom, 44)
                }

                // Flying airplane — separate layer in screen space so it travels edge-to-edge
                // Vertically centered near the title (icon above center offsets the balance slightly)
                Image(systemName: "airplane")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(goldColor)
                    .rotationEffect(.degrees(-45))
                    .shadow(color: goldColor.opacity(0.9), radius: 10)
                    .shadow(color: goldColor.opacity(0.5), radius: 20)
                    .position(x: planeX, y: sh * 0.505)
                    .opacity(planeAlpha)
            }
        }
        .opacity(viewOpacity)
        .onAppear(perform: startAnimation)
    }

    // MARK: - Animation Sequence

    private func startAnimation() {
        // Phase 1 (t=0.15s): Icon badge springs into view
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showIcon = true
        }

        // Phase 2 (t=0.65s): Plane sweeps across, mask reveals the wordmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeInOut(duration: 1.5)) {
                planeProgress = 1.0
            }
        }

        // Phase 3 (t=2.3s): Subtitle and footer fade in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            showSubtitle = true
        }

        // Phase 4 (t=3.1s): Entire view fades out
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            withAnimation(.easeOut(duration: 0.55)) {
                viewOpacity = 0.0
            }
        }

        // Phase 5 (t=3.7s): Remove from hierarchy
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) {
            isVisible = false
        }
    }
}

#Preview {
    SplashScreenView(isVisible: .constant(true))
}
