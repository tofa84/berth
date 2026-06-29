//
//  Pasteboard.swift
//  berth
//
//  Thin wrapper around NSPasteboard for the small "Copy ID / digest / reference"
//  row actions. No engine access.
//

import AppKit

enum Pasteboard {
    static func copy(_ string: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
    }
}
