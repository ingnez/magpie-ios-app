import SwiftUI
import UIKit

enum MagpieTheme {
    static let canvas = Color(red: 0.035, green: 0.043, blue: 0.063)        // #090B10
    static let card = Color(red: 0.071, green: 0.086, blue: 0.125)          // #121620
    static let cardElevated = Color(red: 0.094, green: 0.118, blue: 0.169)  // #181E2B
    static let input = Color(red: 0.055, green: 0.067, blue: 0.102)         // #0E111A
    static let border = Color(red: 0.149, green: 0.184, blue: 0.259)        // #262F42
    static let borderStrong = Color(red: 0.220, green: 0.271, blue: 0.376)  // #384560

    static let amber = Color(red: 0.961, green: 0.651, blue: 0.137)         // #F5A623
    static let amberSoft = Color(red: 0.961, green: 0.651, blue: 0.137).opacity(0.14)
    static let teal = Color(red: 0.176, green: 0.831, blue: 0.749)          // #2DD4BF
    static let tealSoft = Color(red: 0.176, green: 0.831, blue: 0.749).opacity(0.14)
    static let coral = Color(red: 0.957, green: 0.247, blue: 0.369)         // #F43F5E
    static let coralSoft = Color(red: 0.957, green: 0.247, blue: 0.369).opacity(0.14)
    static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)       // #FBBF24
    static let warningSoft = Color(red: 0.984, green: 0.749, blue: 0.141).opacity(0.14)

    static let textPrimary = Color(red: 0.957, green: 0.965, blue: 0.980)   // #F4F6FA
    static let textSecondary = Color(red: 0.580, green: 0.639, blue: 0.722) // #94A3B8
    static let textMuted = Color(red: 0.392, green: 0.455, blue: 0.545)     // #64748B
}

// Custom geometric Magpie emblem (no system icon dependency)
struct MagpieMarkView: View {
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(MagpieTheme.cardElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(MagpieTheme.borderStrong, lineWidth: 1)
                )

            Canvas { ctx, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                    CGPoint(x: w * nx, y: h * ny)
                }

                // Lower teal wing
                var lower = Path()
                lower.move(to: p(0.24, 0.68))
                lower.addLine(to: p(0.50, 0.50))
                lower.addLine(to: p(0.42, 0.78))
                lower.closeSubpath()
                ctx.fill(lower, with: .color(MagpieTheme.teal))

                // Sweeping amber wing
                var wing = Path()
                wing.move(to: p(0.20, 0.58))
                wing.addLine(to: p(0.78, 0.22))
                wing.addLine(to: p(0.56, 0.58))
                wing.addLine(to: p(0.35, 0.70))
                wing.closeSubpath()
                ctx.fill(wing, with: .color(MagpieTheme.amber))

                // Tail prism
                var tail = Path()
                tail.move(to: p(0.56, 0.58))
                tail.addLine(to: p(0.78, 0.22))
                tail.addLine(to: p(0.73, 0.76))
                tail.addLine(to: p(0.47, 0.78))
                tail.closeSubpath()
                ctx.fill(tail, with: .color(Color(red: 0.851, green: 0.467, blue: 0.024)))

                // Core node
                let dotRect = CGRect(x: w * 0.48, y: h * 0.48, width: w * 0.09, height: h * 0.09)
                ctx.fill(Path(ellipseIn: dotRect), with: .color(MagpieTheme.canvas))
            }
            .padding(size * 0.14)
        }
        .frame(width: size, height: size)
    }
}

struct MagpieCard<Content: View>: View {
    var elevated: Bool = false
    var borderColor: Color = MagpieTheme.border
    let content: Content

    init(elevated: Bool = false, borderColor: Color = MagpieTheme.border, @ViewBuilder content: () -> Content) {
        self.elevated = elevated
        self.borderColor = borderColor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(elevated ? MagpieTheme.cardElevated : MagpieTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
    }
}

struct MagpieStatusLight: View {
    let kind: ConnectionStatusKind
    var showPulse: Bool = true
    @State private var pulse = false

    private var lightColor: Color {
        switch kind {
        case .connected: return MagpieTheme.teal
        case .checking: return MagpieTheme.amber
        case .localOnly: return MagpieTheme.warning
        case .failed: return MagpieTheme.coral
        case .untested: return MagpieTheme.textMuted
        }
    }

    var body: some View {
        ZStack {
            if showPulse && (kind == .connected || kind == .checking) {
                Circle()
                    .fill(lightColor.opacity(0.32))
                    .frame(width: 16, height: 16)
                    .scaleEffect(pulse ? 1.25 : 0.75)
                    .opacity(pulse ? 0.15 : 0.65)
            }
            Circle()
                .fill(lightColor)
                .frame(width: 8, height: 8)
                .shadow(color: lightColor.opacity(0.65), radius: 4)
        }
        .frame(width: 16, height: 16)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

struct MagpieToggle: View {
    @Binding var isOn: Bool
    var accent: Color = MagpieTheme.amber

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? accent.opacity(0.24) : MagpieTheme.input)
                    .frame(width: 48, height: 28)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isOn ? accent : MagpieTheme.borderStrong, lineWidth: 1.2)
                    )

                Circle()
                    .fill(isOn ? accent : MagpieTheme.textMuted)
                    .frame(width: 20, height: 20)
                    .padding(4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

enum MagpieButtonTone {
    case primary
    case secondary
    case teal
    case danger
}

struct MagpieButtonStyle: ButtonStyle {
    var tone: MagpieButtonTone = .primary
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        let bg: Color
        let fg: Color
        let border: Color
        switch tone {
        case .primary:
            bg = MagpieTheme.amber
            fg = MagpieTheme.canvas
            border = MagpieTheme.amber
        case .secondary:
            bg = MagpieTheme.cardElevated
            fg = MagpieTheme.textPrimary
            border = MagpieTheme.borderStrong
        case .teal:
            bg = MagpieTheme.tealSoft
            fg = MagpieTheme.teal
            border = MagpieTheme.teal.opacity(0.45)
        case .danger:
            bg = MagpieTheme.coralSoft
            fg = MagpieTheme.coral
            border = MagpieTheme.coral.opacity(0.45)
        }

        return configuration.label
            .font(.system(size: compact ? 12 : 14, weight: .semibold))
            .foregroundColor(fg)
            .padding(.horizontal, compact ? 11 : 15)
            .padding(.vertical, compact ? 7 : 11)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 9 : 12, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct MagpieBadge: View {
    let text: String
    var color: Color = MagpieTheme.teal
    var monospaced: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: monospaced ? .monospaced : .default))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(color.opacity(0.32), lineWidth: 0.8)
            )
    }
}

struct MagpieErrorBanner: View {
    let title: String
    let message: String
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(MagpieTheme.coral)
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(MagpieTheme.textPrimary)
                Spacer()
                if let retryTitle = retryTitle, let onRetry = onRetry {
                    Button(retryTitle, action: onRetry)
                        .buttonStyle(MagpieButtonStyle(tone: .danger, compact: true))
                }
            }
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textPrimary.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagpieTheme.coralSoft)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MagpieTheme.coral.opacity(0.55), lineWidth: 1)
        )
    }
}

struct MagpieInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var monospaced: Bool = false
    var keyboardType: UIKeyboardType = .default
    var errorText: String? = nil
    var helperText: String? = nil

    @State private var revealSecret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(MagpieTheme.textSecondary)

            HStack(spacing: 8) {
                Group {
                    if isSecure && !revealSecret {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                .font(.system(size: 14, design: monospaced ? .monospaced : .default))
                .foregroundColor(MagpieTheme.textPrimary)

                if isSecure {
                    Button {
                        revealSecret.toggle()
                    } label: {
                        Image(systemName: revealSecret ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(MagpieTheme.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(MagpieTheme.input)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(errorText != nil ? MagpieTheme.coral : MagpieTheme.borderStrong, lineWidth: 1)
            )

            if let errorText = errorText {
                Text(errorText)
                    .font(.system(size: 12))
                    .foregroundColor(MagpieTheme.coral)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let helperText = helperText {
                Text(helperText)
                    .font(.system(size: 11.5, design: monospaced ? .monospaced : .default))
                    .foregroundColor(MagpieTheme.teal)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
