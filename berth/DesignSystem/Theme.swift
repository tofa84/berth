//
//  Theme.swift
//  berth
//
//  Color tokens lifted from the Berth design prototype (dark, IBM-Plex based).
//

import SwiftUI

enum Theme {
    // Surfaces
    static let windowBackdrop = Color(hex: 0x0B0C0F)
    static let bg = Color(hex: 0x15171C)          // main content area
    static let toolbar = Color(hex: 0x181B21)
    static let sidebar = Color(hex: 0x121419)
    static let card = Color(hex: 0x1F232B)
    static let cardAlt = Color(hex: 0x1A1D24)
    static let codeBg = Color(hex: 0x0E1014)      // logs / inspect

    // Lines
    static let border = Color.white.opacity(0.06)
    static let borderStrong = Color.white.opacity(0.09)
    static let fill = Color.white.opacity(0.05)

    // Accent
    static let accent = Color(hex: 0xEF9F3B)
    static let onAccent = Color(hex: 0x1C1305)

    // Semantic
    static let green = Color(hex: 0x37C66B)
    static let greenBright = Color(hex: 0x5FCF86)
    static let red = Color(hex: 0xF2787C)
    static let blue = Color(hex: 0x4D8DF6)
    static let blueBright = Color(hex: 0x7FB0FB)
    static let amber = Color(hex: 0xE8A33C)

    // Text
    static let textPrimary = Color(hex: 0xEEF1F5)
    static let textSecondary = Color(hex: 0xCFD5DD)
    static let textTertiary = Color(hex: 0x79828F)
    static let textMuted = Color(hex: 0x6A7382)
    static let textFaint = Color(hex: 0x565F6C)

    static let corner: CGFloat = 12
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}
