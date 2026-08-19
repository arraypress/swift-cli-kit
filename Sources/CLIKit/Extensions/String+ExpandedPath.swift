//
//  String+ExpandedPath.swift
//  CLIKit
//
//  Created by David Sherlock on 2026.
//

import Foundation

public extension String {

    /// The path with a leading `~` expanded to the user's home directory.
    ///
    /// A path typed at a prompt arrives already expanded — the shell does it
    /// before the tool ever runs. A path read from anywhere else does not: a
    /// saved profile, a config file, an MCP argument. Those are exactly the
    /// paths this family passes around, and `~/Invoices` taken literally
    /// creates a directory *named* `~` in the working directory — which then
    /// sits one careless `rm -rf ~` away from being a very bad day.
    var expandedPath: String {
        (self as NSString).expandingTildeInPath
    }
}
