//
//  PowerAssertions.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//
//  The one place CLIKit talks to IOKit's power management. Behind a protocol
//  so the tests can count holds and releases without asking the real system
//  to stay awake — and without needing `pmset` to read the answer back.
//

import Foundation
#if canImport(IOKit)
import IOKit.pwr_mgt
#endif

/// Creates and releases "prevent idle system sleep" assertions.
protocol PowerAssertions: Sendable {

    /// Takes an assertion named `name`; `nil` when the system refused.
    func create(name: String) -> UInt32?

    /// Gives an assertion back.
    func release(_ id: UInt32)
}

/// The real thing: `IOPMAssertionCreateWithName`.
///
/// `PreventUserIdleSystemSleep` is `caffeinate -i`: the machine stays up, the
/// display still sleeps and the screen still locks. Nothing about the user's
/// own power settings changes, and the assertion dies with the process even
/// if it is never released.
struct SystemPowerAssertions: PowerAssertions {

    func create(name: String) -> UInt32? {
        #if canImport(IOKit)
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name as CFString,
            &id
        )
        return result == kIOReturnSuccess ? id : nil
        #else
        return nil
        #endif
    }

    func release(_ id: UInt32) {
        #if canImport(IOKit)
        IOPMAssertionRelease(id)
        #endif
    }
}
