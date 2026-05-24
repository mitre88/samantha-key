import SwiftUI

struct SplashView: View {
    var body: some View {
        ZStack {
            AppTheme.pageBackground
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                VoiceOrb(isListening: true, size: 118)
                VStack(spacing: AppSpacing.xxs) {
                    Text("app.name")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("app.tagline")
                        .font(.callout)
                        .foregroundStyle(AppTheme.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(AppSpacing.xl)
        }
    }
}

struct VoiceOrb: View {
    let isListening: Bool
    var size: CGFloat = 156
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let orbFill = Color.white
    private let orbMark = Color.black.opacity(0.86)
    private let orbInnerRing = Color.black.opacity(0.12)

    var body: some View {
        ZStack {
            Circle()
                .fill(orbFill)
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.08), radius: 24, y: 14)
                .shadow(color: .cyan.opacity(isListening ? 0.22 : 0.08), radius: isListening ? 34 : 18)

            Circle()
                .strokeBorder(orbInnerRing, lineWidth: 1)
                .frame(width: size * 0.82, height: size * 0.82)

            Circle()
                .strokeBorder(AppTheme.voiceTint.opacity(isListening ? 0.34 : 0.14), lineWidth: 2)
                .frame(width: size * 0.98, height: size * 0.98)
                .scaleEffect(isListening && !reduceMotion ? 1.08 : 1)
                .opacity(isListening ? 0.7 : 0.35)

            OrbWaveformMark(size: size * 0.32, color: orbMark, isListening: isListening)
        }
        .scaleEffect(isListening && !reduceMotion ? 1.03 : 1)
        .animation(reduceMotion ? nil : .smooth(duration: 1.2).repeatForever(autoreverses: true), value: isListening)
        .accessibilityLabel(Text("accessibility.voice_orb"))
    }
}

private struct OrbWaveformMark: View {
    let size: CGFloat
    let color: Color
    let isListening: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let levels: [CGFloat] = [0.42, 0.72, 1.0, 0.72, 0.42]

    var body: some View {
        HStack(alignment: .center, spacing: size * 0.11) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: max(size * 0.12, 4), height: size * levels[index])
                    .scaleEffect(y: animatedScale(for: index), anchor: .center)
            }
        }
        .frame(width: size * 1.22, height: size)
        .animation(reduceMotion ? nil : .smooth(duration: 0.75).repeatForever(autoreverses: true).delay(Double(levels.count - 1) * 0.015), value: isListening)
    }

    private func animatedScale(for index: Int) -> CGFloat {
        guard isListening && !reduceMotion else { return 1 }
        return index.isMultiple(of: 2) ? 1.12 : 0.9
    }
}
