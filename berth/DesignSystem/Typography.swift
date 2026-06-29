//
//  Typography.swift
//  berth
//
//  Centralized font helpers. The design uses IBM Plex Sans / IBM Plex Mono.
//  Until the .otf files are bundled, these map to the system fonts (mono uses
//  the monospaced design) — swap the two factory methods below to adopt Plex.
//

import SwiftUI

enum BerthFont {
    static let sansName: String? = nil   // e.g. "IBMPlexSans" once bundled
    static let monoName: String? = nil   // e.g. "IBMPlexMono" once bundled

    static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let sansName { return .custom(sansName, fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        if let monoName { return .custom(monoName, fixedSize: size).weight(weight) }
        return .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Font {
    static func berthSans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        BerthFont.sans(size, weight)
    }
    static func berthMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        BerthFont.mono(size, weight)
    }
}
