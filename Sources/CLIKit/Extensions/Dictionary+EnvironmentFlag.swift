//
//  Dictionary+EnvironmentFlag.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

extension Dictionary where Key == String, Value == String {

    /// Whether an on/off environment variable is switched on: `1`, `true` or
    /// `yes`, in any case. Unset, empty and anything else mean off.
    func flagIsSet(_ key: String) -> Bool {
        guard let value = self[key]?.lowercased(), !value.isEmpty else { return false }
        return ["1", "true", "yes"].contains(value)
    }
}
