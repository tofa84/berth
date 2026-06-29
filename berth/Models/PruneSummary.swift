//
//  PruneSummary.swift
//  berth
//
//  Shared error summary for best-effort prune loops (images, volumes,
//  containers). Each loop keeps going past individual failures and collects
//  them, then surfaces one toast covering all of them instead of only the last.
//

import Foundation

/// Builds a single user-facing error string from the failures of a best-effort
/// loop that attempted `total` operations. Returns `nil` when nothing failed.
func pruneSummary(_ failures: [String], of total: Int, noun: String) -> String? {
    guard !failures.isEmpty else { return nil }
    if failures.count == 1 { return failures[0] }
    return "\(failures.count) of \(total) \(noun) failed: \(failures.joined(separator: "; "))"
}
