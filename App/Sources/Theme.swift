import SwiftUI
import UIKit

enum Theme {
    static let accent = Color(light: 0xE8590C, dark: 0xFF8A3D)
    static let good = Color(light: 0x2B8A3E, dark: 0x2F9E44)
    static let again = Color(light: 0xC92A2A, dark: 0xE03131)
    static let easy = Color(light: 0x1971C2, dark: 0x1C7ED6)
    static let card = Color(light: 0xFFFFFF, dark: 0x221F2A)
    static let background = Color(light: 0xF6F3EE, dark: 0x131117)
    static let glowA = Color(light: 0xFFC89A, dark: 0x7A2E0E)
    static let glowB = Color(light: 0xFFB3C1, dark: 0x5A1E4A)
    static let glowC = Color(light: 0xFFE3A3, dark: 0x3A2470)

    /// Per-deck tint so a shuffled session still shows at a glance which subject a card is from.
    static func deckColor(_ deck: String) -> Color {
        let hex = deckHex(deck)
        return Color(light: hex, dark: hex)
    }

    /// Mid-tone hues that read on both the light and dark card backgrounds.
    static func deckHex(_ deck: String) -> UInt32 {
        let palette: [UInt32] = [0xF08C00, 0xE64980, 0x9C36B5, 0x5C7CFA, 0x12B886, 0x40C057, 0x15AABF, 0x339AF0, 0xFA5252, 0xA9822F]
        let index = deck.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count
        return palette[index]
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func flip() { UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.8) }
    static func grade(_ success: Bool) { UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .warning) }
    static func celebrate() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}
