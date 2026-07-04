//
//  KeyValueEntry.swift
//  berth
//
//  Shared KEY=VALUE plumbing: the split rule used wherever the engine hands us
//  (or we hand it) "KEY=VALUE" strings — env vars, build args, labels — and the
//  editable row model behind the Run/Build form lists.
//

import Foundation

enum KeyValueEntry {
    /// Split a `KEY=VALUE` entry at the *first* `=` — values may contain `=`
    /// themselves. Entries without one become a key with an empty value.
    nonisolated static func split(_ entry: String) -> (key: String, value: String) {
        guard let eq = entry.firstIndex(of: "=") else { return (entry, "") }
        return (String(entry[..<eq]), String(entry[entry.index(after: eq)...]))
    }
}

/// One editable KEY=VALUE row in the Run/Build forms (env vars, build args,
/// labels). The stable `id` keeps SwiftUI rows identified while both fields
/// are edited in place.
struct KeyValueField: Identifiable {
    let id = UUID()
    var key = ""
    var value = ""
}

extension KeyValueField {
    /// Parse an engine-shaped "KEY=VALUE" entry (re-run prefill).
    init(entry: String) {
        let (key, value) = KeyValueEntry.split(entry)
        self.init(key: key, value: value)
    }
}
