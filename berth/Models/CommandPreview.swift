//
//  CommandPreview.swift
//  berth
//
//  Renders an argument vector as the equivalent `container …` CLI command for
//  the live preview in the Run/Build sheets. Display-only quoting — the argv
//  itself is passed to the process un-quoted.
//

import Foundation

enum CommandPreview {
    static func container(_ argv: [String]) -> String {
        (["container"] + argv).map(quote).joined(separator: " ")
    }

    /// Wrap arguments containing spaces so the preview stays copy-pasteable.
    private static func quote(_ s: String) -> String {
        s.contains(" ") ? "\"\(s)\"" : s
    }
}
