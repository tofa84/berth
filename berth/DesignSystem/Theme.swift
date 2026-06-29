//
//  Theme.swift
//  berth
//
//  Color tokens lifted from the Berth design prototype (IBM-Plex based).
//  Every token is appearance-adaptive: a `dark` value (the original prototype)
//  and a `light` value (a cool, System-Settings-style ramp). The values resolve
//  per system appearance and re-evaluate live when the user flips Light/Dark.
//

import SwiftUI
import AppKit

enum Theme {
    // Surfaces — light is a cool-neutral ramp: white cards float on a light-gray
    // canvas; chrome recedes by getting grayer; codeBg reads as an inset panel.
    static let windowBackdrop = Color(light: 0xE3E5E9, dark: 0x0B0C0F)
    static let bg             = Color(light: 0xF4F5F7, dark: 0x15171C)   // main content area
    static let toolbar        = Color(light: 0xECEDF0, dark: 0x181B21)
    static let sidebar        = Color(light: 0xE8EAEE, dark: 0x121419)
    static let card           = Color(light: 0xFFFFFF, dark: 0x1F232B)
    static let cardAlt        = Color(light: 0xF9FAFB, dark: 0x1A1D24)
    static let codeBg         = Color(light: 0xEDEFF3, dark: 0x0E1014)   // logs / inspect

    // Lines — translucent "ink" whose polarity flips by appearance:
    // black hairlines over light surfaces, white over dark.
    static let border       = Color.ink(light: 0.10, dark: 0.06)
    static let borderStrong = Color.ink(light: 0.15, dark: 0.09)
    static let fill         = Color.ink(light: 0.06, dark: 0.05)

    // Accent — amber identity, deepened in light so it clears contrast on near-white.
    static let accent   = Color(light: 0xCB7D14, dark: 0xEF9F3B)
    static let onAccent = Color(light: 0x271A05, dark: 0x1C1305)

    // Semantic — darkened/saturated in light so status hues stay legible on light surfaces.
    static let green       = Color(light: 0x158A42, dark: 0x37C66B)
    static let greenBright = Color(light: 0x1FA453, dark: 0x5FCF86)
    static let red         = Color(light: 0xD23B3F, dark: 0xF2787C)
    static let blue        = Color(light: 0x186DDD, dark: 0x4D8DF6)
    static let blueBright  = Color(light: 0x3D86F0, dark: 0x7FB0FB)
    static let amber       = Color(light: 0x8C5A00, dark: 0xE8A33C)

    // Text — dark-on-light / light-on-dark, preserving the five-step hierarchy.
    static let textPrimary   = Color(light: 0x16181C, dark: 0xEEF1F5)
    static let textSecondary = Color(light: 0x3A3E45, dark: 0xCFD5DD)
    static let textTertiary  = Color(light: 0x676D75, dark: 0x79828F)
    static let textMuted     = Color(light: 0x868D96, dark: 0x6A7382)
    static let textFaint     = Color(light: 0xA6ACB4, dark: 0x565F6C)

    // Effects
    static let chartTrack = Color.ink(light: 0.09, dark: 0.07)   // donut gauge unfilled ring
    static let cardShadow = Color(light: 0x000000, dark: 0x000000, lightOpacity: 0.08, darkOpacity: 0.40)

    static let corner: CGFloat = 12
}

extension Color {
    /// Fixed sRGB color from a 0xRRGGBB hex (kept for one-off brand marks).
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }

    /// Appearance-adaptive color: resolves to `light` under Aqua, `dark` under Dark Aqua,
    /// re-evaluated live by AppKit when the system appearance changes. Each value is a
    /// 0xRRGGBB hex with an optional per-appearance opacity.
    init(light: UInt32, dark: UInt32, lightOpacity: Double = 1.0, darkOpacity: Double = 1.0) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(
                srgbRed: Double((hex >> 16) & 0xFF) / 255.0,
                green: Double((hex >> 8) & 0xFF) / 255.0,
                blue: Double(hex & 0xFF) / 255.0,
                alpha: isDark ? darkOpacity : lightOpacity
            )
        })
    }

    /// Translucent overlay whose polarity flips by appearance — black ink over light
    /// surfaces, white ink over dark — for hairlines, fills, and gauge tracks.
    static func ink(light: Double, dark: Double) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: dark)
                : NSColor(white: 0.0, alpha: light)
        })
    }
}
