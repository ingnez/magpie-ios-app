import SwiftUI
import UIKit

// MARK: - Unified Design Tokens

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let cardGap: CGFloat = 14
    static let lg: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let sheetPadding: CGFloat = 20
    static let pageHorizontal: CGFloat = 22
    static let sectionGap: CGFloat = 22
    static let pageTop: CGFloat = 24
    static let pageBottom: CGFloat = 100
}

enum Corners {
    static let xs: CGFloat = 5
    static let sm: CGFloat = 7
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 14
}

enum Typography {
    static let heroTitle = Font.system(size: 28, weight: .semibold)
    static let pageTitle = Font.system(size: 24, weight: .semibold)
    static let sheetTitle = Font.system(size: 17, weight: .semibold)
    static let cardTitle = Font.system(size: 15.5, weight: .semibold)
    static let navTitle = Font.system(size: 15, weight: .semibold)
    static let bodyLarge = Font.system(size: 14.5, weight: .semibold)
    static let bodyMedium = Font.system(size: 14, weight: .medium)
    static let rowTitle = Font.system(size: 13.5, weight: .semibold)
    static let rowTitleMono = Font.system(size: 13.5, weight: .semibold, design: .monospaced)
    static let bodyInput = Font.system(size: 13.5)
    static let bodyInputMono = Font.system(size: 13.5, design: .monospaced)
    static let body = Font.system(size: 13)
    static let bodyMono = Font.system(size: 13, design: .monospaced)
    static let bodySmall = Font.system(size: 12.5)
    static let bodySmallMedium = Font.system(size: 12.5, weight: .medium)
    static let bodySmallMono = Font.system(size: 12.5, design: .monospaced)
    static let sectionHeader = Font.system(size: 12, weight: .medium)
    static let sectionHeaderMono = Font.system(size: 12, design: .monospaced)
    static let caption = Font.system(size: 11.5)
    static let captionMedium = Font.system(size: 11.5, weight: .medium)
    static let captionMono = Font.system(size: 11.5, design: .monospaced)
    static let micro = Font.system(size: 11)
    static let microMedium = Font.system(size: 11, weight: .medium)
    static let microSemibold = Font.system(size: 11, weight: .semibold)
    static let microMono = Font.system(size: 11, design: .monospaced)
    static let nano = Font.system(size: 10.5)
    static let nanoMono = Font.system(size: 10.5, design: .monospaced)
}

enum StatusPalette {
    fileprivate static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? dark : light
        })
    }

    static let ok = dynamic(
        light: UIColor(red: 0.086, green: 0.502, blue: 0.290, alpha: 1.0), // #16804A
        dark: UIColor(red: 0.204, green: 0.827, blue: 0.600, alpha: 1.0)   // #34D399
    )
    static let okSurface = dynamic(
        light: UIColor(red: 0.086, green: 0.502, blue: 0.290, alpha: 0.09),
        dark: UIColor(red: 0.204, green: 0.827, blue: 0.600, alpha: 0.16)
    )

    static let warn = dynamic(
        light: UIColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 1.0), // #B45309
        dark: UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 1.0)   // #FBBF24
    )
    static let warnSurface = dynamic(
        light: UIColor(red: 0.706, green: 0.325, blue: 0.035, alpha: 0.09),
        dark: UIColor(red: 0.984, green: 0.749, blue: 0.141, alpha: 0.16)
    )

    static let err = dynamic(
        light: UIColor(red: 0.725, green: 0.110, blue: 0.110, alpha: 1.0), // #B91C1C
        dark: UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 1.0)   // #F87171
    )
    static let errSurface = dynamic(
        light: UIColor(red: 0.725, green: 0.110, blue: 0.110, alpha: 0.09),
        dark: UIColor(red: 0.973, green: 0.443, blue: 0.443, alpha: 0.16)
    )

    static let neutral = MagpieTheme.textMuted
    static let neutralSurface = MagpieTheme.surfaceSubtle
}

enum MagpieTheme {
    // Adaptive Semantic Paper & Ink Palette (Light + Dark)
    static let canvas = StatusPalette.dynamic(
        light: UIColor(red: 0.969, green: 0.965, blue: 0.949, alpha: 1.0), // #F7F6F2
        dark: UIColor(red: 0.059, green: 0.059, blue: 0.055, alpha: 1.0)   // #0F0F0E
    )
    static let surface = StatusPalette.dynamic(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0), // #FFFFFF
        dark: UIColor(red: 0.102, green: 0.102, blue: 0.094, alpha: 1.0)   // #1A1A18
    )
    static let surfaceElevated = StatusPalette.dynamic(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0), // #FFFFFF
        dark: UIColor(red: 0.133, green: 0.133, blue: 0.125, alpha: 1.0)   // #222220
    )
    static let surfaceSubtle = StatusPalette.dynamic(
        light: UIColor(red: 0.937, green: 0.929, blue: 0.906, alpha: 1.0), // #EFECE7
        dark: UIColor(red: 0.149, green: 0.149, blue: 0.137, alpha: 1.0)   // #262623
    )
    static let hairline = StatusPalette.dynamic(
        light: UIColor(red: 0.890, green: 0.882, blue: 0.855, alpha: 1.0), // #E3E1DA
        dark: UIColor(red: 0.200, green: 0.200, blue: 0.184, alpha: 1.0)   // #33332F
    )

    static let ink = StatusPalette.dynamic(
        light: UIColor(red: 0.078, green: 0.078, blue: 0.075, alpha: 1.0), // #141413
        dark: UIColor(red: 0.953, green: 0.949, blue: 0.933, alpha: 1.0)   // #F3F2EE
    )
    static let onInk = StatusPalette.dynamic(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0), // #FFFFFF
        dark: UIColor(red: 0.071, green: 0.071, blue: 0.063, alpha: 1.0)   // #121210
    )
    static let toggleThumbOff = StatusPalette.dynamic(
        light: UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.0), // #FFFFFF
        dark: UIColor(red: 0.784, green: 0.776, blue: 0.745, alpha: 1.0)   // #C8C6BE
    )
    static let textSecondary = StatusPalette.dynamic(
        light: UIColor(red: 0.420, green: 0.416, blue: 0.396, alpha: 1.0), // #6B6A65
        dark: UIColor(red: 0.710, green: 0.702, blue: 0.671, alpha: 1.0)   // #B5B3AB
    )
    static let textMuted = StatusPalette.dynamic(
        light: UIColor(red: 0.612, green: 0.604, blue: 0.573, alpha: 1.0), // #9C9A92
        dark: UIColor(red: 0.525, green: 0.518, blue: 0.486, alpha: 1.0)   // #86847C
    )

    // Restrained semantic accents (forwarded from StatusPalette)
    static let ok = StatusPalette.ok
    static let warn = StatusPalette.warn
    static let err = StatusPalette.err
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
                ctx.fill(wing, with: .color(MagpieTheme.onInk))

                var tail = Path()
                tail.move(to: p(0.54, 0.62))
                tail.addLine(to: p(0.74, 0.76))
                tail.addLine(to: p(0.42, 0.76))
                tail.closeSubpath()
                ctx.fill(tail, with: .color(MagpieTheme.onInk.opacity(0.65)))
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
        VStack(alignment: .leading, spacing: Spacing.sm + 2) {
            if title != nil || trailingText != nil {
                HStack(alignment: .firstTextBaseline) {
                    if let title = title {
                        Text(title)
                            .font(Typography.sectionHeader)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    Spacer()
                    if let trailingText = trailingText {
                        Text(trailingText)
                            .font(Typography.captionMono)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: Spacing.cardGap) {
                content
            }
            .padding(Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MagpieTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Corners.xl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Corners.xl, style: .continuous)
                    .stroke(MagpieTheme.hairline, lineWidth: 1)
            )
        }
    }
}

struct MagpieStatusLight: View {
    let kind: ConnectionStatusKind

    private var dotColor: Color {
        switch kind {
        case .connected: return StatusPalette.ok
        case .checking: return StatusPalette.warn
        case .localOnly: return MagpieTheme.ink
        case .failed: return StatusPalette.err
        case .untested: return StatusPalette.neutral
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
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(isOn ? Color.clear : MagpieTheme.hairline, lineWidth: 1)
                    )
                    .frame(width: 44, height: 26)

                Circle()
                    .fill(isOn ? MagpieTheme.onInk : MagpieTheme.toggleThumbOff)
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
            fg = MagpieTheme.onInk
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
            bg = StatusPalette.errSurface
            fg = StatusPalette.err
            border = StatusPalette.err.opacity(0.35)
        }

        return configuration.label
            .font(.system(size: compact ? 12.5 : 14, weight: .medium))
            .foregroundColor(fg)
            .padding(.horizontal, compact ? Spacing.md : Spacing.lg)
            .padding(.vertical, compact ? 7 : 11)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: compact ? Corners.sm + 1 : Corners.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: compact ? Corners.sm + 1 : Corners.md, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.72 : 1.0)
    }
}

struct MagpieTag: View {
    let text: String
    var tone: Color = MagpieTheme.textSecondary
    var background: Color = MagpieTheme.surfaceSubtle
    var monospaced: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: monospaced ? .monospaced : .default))
            .foregroundColor(tone)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Corners.xs, style: .continuous))
    }
}

struct MagpieErrorBanner: View {
    let title: String
    let message: String
    var detail: String? = nil
    var retryTitle: String? = nil
    var onRetry: (() -> Void)? = nil

    @State private var showDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Circle()
                    .fill(StatusPalette.err)
                    .frame(width: 6, height: 6)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(MagpieTheme.ink)
                Spacer()
                if let retryTitle = retryTitle, let onRetry = onRetry {
                    Button(retryTitle, action: onRetry)
                        .font(Typography.sectionHeader)
                        .foregroundColor(StatusPalette.err)
                }
            }
            Text(message)
                .font(Typography.bodySmall)
                .foregroundColor(MagpieTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let detail = detail, !detail.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showDetail.toggle()
                        }
                    } label: {
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: showDetail ? "chevron.down" : "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text(showDetail ? "收起原文细节" : "查看原文细节")
                                .font(Typography.captionMedium)
                        }
                        .foregroundColor(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)

                    if showDetail {
                        Text(detail)
                            .font(Typography.microMono)
                            .foregroundColor(MagpieTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(MagpieTheme.canvas)
                            .clipShape(RoundedRectangle(cornerRadius: Corners.sm - 1, style: .continuous))
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Spacing.cardGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StatusPalette.errSurface)
        .clipShape(RoundedRectangle(cornerRadius: Corners.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Corners.lg, style: .continuous)
                .stroke(StatusPalette.err.opacity(0.35), lineWidth: 1)
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
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(label)
                .font(Typography.sectionHeader)
                .foregroundColor(MagpieTheme.textSecondary)

            HStack(spacing: Spacing.sm) {
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
                            .font(Typography.captionMedium)
                            .foregroundColor(MagpieTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(MagpieTheme.canvas)
            .clipShape(RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Corners.sm + 1, style: .continuous)
                    .stroke(errorText != nil ? StatusPalette.err.opacity(0.55) : MagpieTheme.hairline, lineWidth: 1)
            )

            if let errorText = errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(Typography.caption)
                    .foregroundColor(StatusPalette.err)
            } else if let helperText = helperText, !helperText.isEmpty {
                Text(helperText)
                    .font(Typography.caption)
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
        if clamped >= 0.9 { return StatusPalette.err }
        if clamped >= 0.7 { return StatusPalette.warn }
        return StatusPalette.ok
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
