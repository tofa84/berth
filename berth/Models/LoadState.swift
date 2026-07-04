//
//  LoadState.swift
//  berth
//
//  Generic async-load state used by the per-screen stores.
//

import Foundation

enum LoadState<Value: Sendable>: Sendable {
    case idle
    case loading
    case loaded(Value)
    case failed(String)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var errorText: String? {
        if case .failed(let m) = self { return m }
        return nil
    }
}
