//
//  DisplayHost.swift
//  berth
//
//  Single source of truth for the local machine identity shown in the UI:
//  the display name and the machine spec (cores / memory).
//

import Foundation

/// Display name for the local machine, used everywhere the host name appears
/// (sidebar status card, top-bar breadcrumb, System screen).
///
/// Set ``placeholder`` to a non-nil value to mask the real host name — handy for
/// screenshots and docs. Set it back to `nil` to show the real name again.
enum DisplayHost {
    /// Override shown everywhere instead of the real host name. `nil` = real name.
    static let placeholder: String? = nil

    /// The name to render, with the redundant ".local" Bonjour suffix stripped.
    static var name: String {
        if let placeholder { return placeholder }
        return displayName(from: ProcessInfo.processInfo.hostName)
    }

    /// Strips the redundant ".local" Bonjour suffix from a raw host name.
    nonisolated static func displayName(from hostName: String) -> String {
        hostName.hasSuffix(".local") ? String(hostName.dropLast(6)) : hostName
    }
}

/// Machine spec facts shown next to the host name (sidebar status card,
/// System screen's Host card).
enum HostInfo {
    static var cores: Int { ProcessInfo.processInfo.processorCount }

    /// Physical memory rounded to whole gigabytes.
    static var memoryGB: Int {
        Int((Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824).rounded())
    }
}
