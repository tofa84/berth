//
//  DisplayHost.swift
//  berth
//
//  Single source of truth for the local machine name shown in the UI.
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
