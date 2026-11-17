import SwiftUI
import UIKit

enum MagpieTheme {
    // Minimalist Paper & Ink Palette (5 core tokens)
    static let canvas = Color(red: 0.969, green: 0.965, blue: 0.949)        // #F7F6F2 Warm Alabaster
    static let surface = Color.white                                        // #FFFFFF Pure Surface
    static let surfaceSubtle = Color(red: 0.937, green: 0.929, blue: 0.906) // #EFECE7 Subtle Stone
    static let hairline = Color(red: 0.890, green: 0.882, blue: 0.855)      // #E3E1DA 1pt Rule

    static let ink = Color(red: 0.078, green: 0.078, blue: 0.075)           // #141413 Primary Ink
    static let textSecondary = Color(red: 0.420, green: 0.416, blue: 0.396) // #6B6A65 Secondary Graphite
    static let textMuted = Color(red: 0.612, green: 0.604, blue: 0.573)     // #9C9A92 Muted Stone

    // Restrained semantic accents (used only for status dots & critical states)
    static let ok = Color(red: 0.086, green: 0.502, blue: 0.290)            // #16804A Forest Green
    static let warn = Color(red: 0.706, green: 0.325, blue: 0.035)          // #B45309 Ochre
    static let err = Color(red: 0.725, green: 0.110, blue: 0.110)           // #B91C1C Crimson
}

struct MagpieMarkView: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(MagpieTheme.ink)

            Canvas { ctx, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                func p(_ nx: CGFloat, _ ny: CGFloat) -> CGPoint {
                    CGPoint(x: w * nx, y: h * ny)
                }

                var wing = Path()
                wing.move(to: p(0.22, 0.64))
                wing.addLine(to: p(0.78, 0.24))
                wing.addLine(to: p(0.56, 0.62))
                wing.closeSubpath()
                ctx.fill(wing, with: .color(MagpieTheme.surface))

                var tail = Path()
                tail.move(to: p(0.54, 0.62))
                tail.addLine(to: p(0.74, 0.76))
                tail.addLine(to: p(0.42, 0.76))
                tail.closeSubpath()
                ctx.fill(tail, with: .color(MagpieTheme.surface.opacity(0.65)))
            }
        }
        .frame(width: size, height: size)
    }
}

struct MinimalSection<Content: View>: View {
    var title: String? = nil
    var trailingText: String? = nil
    let content: Content

    init(title: String? = nil, trailingText: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailingText = trailingText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailingText != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title = title {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Spacer()
                    if let trailingText = trailingText {
                        Text(trailingText)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MagpieTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(MagpieTheme.hairline, lineWidth: 1)
            )
        }
    }
}

struct MagpieStatusLight: View {
    let kind: ConnectionStatusKind

    private var dotColor: Color {
        switch kind {
        case .connected: return MagpieTheme.ok
        case .checking: return MagpieTheme.warn
        case .localOnly: return MagpieTheme.ink
        case .failed: return MagpieTheme.err
        case .untested: return MagpieTheme.textMuted
        }
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 7, height: 7)
    }
}

struct MagpieToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isOn ? MagpieTheme.ink : MagpieTheme.surfaceSubtle)
                    .frame(width: 44, height: 26)

                Circle()
                    .fill(MagpieTheme.surface)
                    .frame(width: 20, height: 20)
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

enum MagpieButtonTone {
    case primary
    case secondary
    case subtle
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
            bg = MagpieTheme.ink
            fg = MagpieTheme.surface
            border = MagpieTheme.ink
        case .secondary:
            bg = MagpieTheme.surface
            fg = MagpieTheme.ink
            border = MagpieTheme.hairline
        case .subtle:
            bg = MagpieTheme.surfaceSubtle
            fg = MagpieTheme.ink
            border = Color.clear
        case .danger:
            bg = MagpieTheme.surface
            fg = MagpieTheme.err
            border = MagpieTheme.err.opacity(0.3)
        }

        return configuration.label
            .font(.system(size: compact ? 12.5 : 14, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 7 : 11)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1.0)
    }
}

struct MagpieTag: View {
    let text: String
    var tone: Color = MagpieTheme.textSecondary
    var monospaced: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundColor(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(MagpieTheme.surfaceSubtle)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

struct MagpieErrorBanner: View {
    let title: String
    let message: String
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(MagpieTheme.err)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if let retryTitle = retryTitle, let onRetry = onRetry {
                    Button(retryTitle, action: onRetry)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(MagpieTheme.err)
                }
            }
            Text(message)
                .font(.system(size: 12.5))
                .foregroundColor(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MagpieTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MagpieTheme.err.opacity(0.35), lineWidth: 1)
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
    var accessibilityId: String? = nil

    @State private var revealSecret = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 13.5, design: monospaced ? .monospaced : .default))
                .foregroundColor(MagpieTheme.ink)
                .accessibilityIdentifier(accessibilityId ?? placeholder)

                if isSecure {
                    Button {
                        revealSecret.toggle()
                    } label: {
                        Text(revealSecret ? "隐藏" : "显示")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MagpieTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(errorText != nil ? MagpieTheme.err.opacity(0.5) : MagpieTheme.hairline, lineWidth: 1)
            )

            if let errorText = errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.err)
            } else if let helperText = helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(.system(size: 11.5))
                    .foregroundColor(MagpieTheme.textMuted)
            }
        }
    }
}

struct MagpieProgressBar: View {
    let ratio: Double // 0.0 ... 1.0

    private var clamped: Double {
        min(max(ratio, 0.0), 1.0)
    }

    private var barColor: Color {
        if clamped >= 0.9 { return MagpieTheme.err }
        if clamped >= 0.7 { return MagpieTheme.warn }
        return MagpieTheme.ink
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(MagpieTheme.surfaceSubtle)
                Capsule(style: .continuous)
                    .fill(barColor)
                    .frame(width: max(clamped > 0 ? 4 : 0, geo.size.width * clamped))
            }
        }
        .frame(height: 5)
    }
}
