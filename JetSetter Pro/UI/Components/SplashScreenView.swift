// SplashScreenView.swift

import SwiftUI

struct SplashScreenView: View {
    @Binding var isVisible: Bool

    @State private var showIcon = false
    @State private var planeProgress: CGFloat = 0
    @State private var showSubtitle = false
    @State private var viewOpacity: Double = 1.0

    private let bgColor     = Color(hex: "#10131E")
    private let accentColor = JetsetterTheme.Colors.accent

    var body: some View {
        GeometryReader { geo in
            let sw = geo.size.width
            let sh = geo.size.height
            let planeX = -80 + planeProgress * (sw + 160)
            let revealWidth = max(0, planeX - 50)
            let planeAlpha = min(1.0, min(planeProgress * 30, (1.0 - planeProgress) * 30))

            ZStack {
                bgColor.ignoresSafeArea()

                // Subtle radial glow centered on screen
                RadialGradient(
                    colors: [accentColor.opacity(0.10), .clear],
                    center: .center,
                    startRadius: 10,
                    endRadius: sw * 0.85
                )
                .ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    // Circular icon badge
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [accentColor.opacity(0.22), accentColor.opacity(0.04)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 45
                                )
                            )
                            .frame(width: 90, height: 90)
                            .overlay(Circle().stroke(accentColor.opacity(0.30), lineWidth: 1))

                        Image(systemName: "airplane")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(accentColor)
                            .rotationEffect(.degrees(-45))
                    }
                    .scaleEffect(showIcon ? 1.0 : 0.2)
                    .opacity(showIcon ? 1.0 : 0.0)
                    .animation(.spring(response: 0.55, dampingFraction: 0.62), value: showIcon)

                    // Wordmark revealed by growing mask as the plane crosses
                    Text("JetSetter Pro")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [accentColor, accentColor.opacity(0.88), Color(hex: "#A8D8FF")],
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
                        .foregroundStyle(accentColor.opacity(0.40))
                        .opacity(showSubtitle ? 1.0 : 0.0)
                        .animation(.easeIn(duration: 0.7).delay(0.25), value: showSubtitle)
                        .padding(.bottom, 44)
                }

                // Flying airplane — travels edge-to-edge
                Image(systemName: "airplane")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(accentColor)
                    .rotationEffect(.degrees(-45))
                    .shadow(color: accentColor.opacity(0.85), radius: 10)
                    .shadow(color: accentColor.opacity(0.45), radius: 20)
                    .position(x: planeX, y: sh * 0.505)
                    .opacity(planeAlpha)
            }
        }
        .opacity(viewOpacity)
        .onAppear(perform: startAnimation)
    }

    // MARK: - Animation Sequence

    private func startAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            showIcon = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation(.easeInOut(duration: 1.5)) {
                planeProgress = 1.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            showSubtitle = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) {
            withAnimation(.easeOut(duration: 0.55)) {
                viewOpacity = 0.0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.7) {
            isVisible = false
        }
    }
}

#Preview {
    SplashScreenView(isVisible: .constant(true))
}
