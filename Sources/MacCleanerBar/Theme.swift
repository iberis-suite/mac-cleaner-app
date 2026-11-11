import AppKit
import SwiftUI

enum Theme {
    private static func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func pair(_ light: NSColor, _ dark: NSColor) -> NSColor {
        NSColor(name: nil) { a in a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
    }

    private static func color(_ light: NSColor, _ dark: NSColor) -> Color { Color(nsColor: pair(light, dark)) }

    static let accent = color(rgb(0x1E6BF0), rgb(0x3B8BFF))
    static let accentLight = color(rgb(0x3D86FF), rgb(0x5AA2FF))
    static let accentDeep = color(rgb(0x1257D6), rgb(0x1E68F0))
    static let onAccent = Color.white

    static let backgroundTop = color(rgb(0xF4F8FF), rgb(0x1A2D5A))
    static let backgroundMid = color(rgb(0xE8F0FF), rgb(0x0F1D40))
    static let backgroundBottom = color(rgb(0xDCE8FF), rgb(0x0A142E))
    static let sidebar = color(rgb(0xFFFFFF, 0.45), rgb(0x06102A, 0.45))

    static let card = color(rgb(0xFFFFFF, 0.72), rgb(0xFFFFFF, 0.06))
    static let cardBorder = color(rgb(0x1E6BF0, 0.14), rgb(0xFFFFFF, 0.13))
    static let cardHover = color(rgb(0x1E6BF0, 0.08), rgb(0xFFFFFF, 0.09))
    static let tile = color(rgb(0x1E6BF0, 0.10), rgb(0x3B8BFF, 0.16))
    static let tileBorder = color(rgb(0x1E6BF0, 0.12), rgb(0xFFFFFF, 0.10))
    static let field = color(rgb(0xFFFFFF, 0.85), rgb(0xFFFFFF, 0.07))
    static let track = color(rgb(0x1E6BF0, 0.12), rgb(0xFFFFFF, 0.10))
    static let selection = color(rgb(0x1E6BF0, 0.12), rgb(0x3B8BFF, 0.22))
    static let divider = color(rgb(0x1E6BF0, 0.14), rgb(0xFFFFFF, 0.12))
    static let console = color(rgb(0x0A142E, 0.06), rgb(0x000000, 0.30))

    static let good = color(rgb(0x1E9E4A), rgb(0x4ADE80))
    static let warn = color(rgb(0xD97706), rgb(0xFBBF24))
    static let bad = color(rgb(0xDC2626), rgb(0xF87171))
    static let destructive = color(rgb(0xE5484D), rgb(0xEF5B5B))
    static let warnFill = color(rgb(0xD97706, 0.12), rgb(0xFBBF24, 0.12))

    static let levelNS: [NSColor] = [
        pair(rgb(0x1E9E4A), rgb(0x4ADE80)), pair(rgb(0xD97706), rgb(0xFBBF24)), pair(rgb(0xDC2626), rgb(0xF87171)),
    ]

    static var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundMid, backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var button: LinearGradient {
        LinearGradient(colors: [accentLight, accentDeep], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    static var accentBlue: Color { Theme.accent }

    static func level(_ l: Int) -> Color { Color(nsColor: Theme.levelNS[max(0, min(2, l))]) }
}

extension View {
    func themeCard(_ radius: CGFloat = 12) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }

    func themeTile(_ radius: CGFloat = 8) -> some View {
        background(Theme.tile, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.tileBorder, lineWidth: 1))
    }

    func themeField(_ radius: CGFloat = 9) -> some View {
        background(Theme.field, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.cardBorder, lineWidth: 1))
    }
}

struct IconTile: View {
    let symbol: String
    var size: CGFloat = 30
    var font: CGFloat = 14

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: font, weight: .medium))
            .foregroundStyle(Theme.accent)
            .frame(width: size, height: size)
            .themeTile(size * 0.27)
    }
}
