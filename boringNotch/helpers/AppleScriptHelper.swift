//
//  AppleScriptHelper.swift
//  boringNotch
//
//  Created by Alexander on 2025-03-29.
//

import AppKit
import Foundation

class AppleScriptHelper {
    @discardableResult
    class func execute(_ scriptText: String) async throws -> NSAppleEventDescriptor? {
        try await withCheckedThrowingContinuation { continuation in
            Task.detached(priority: .userInitiated) {
                let script = NSAppleScript(source: scriptText)
                var error: NSDictionary?
                if let descriptor = script?.executeAndReturnError(&error) {
                    continuation.resume(returning: descriptor)
                } else if let error = error {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: error as? [String: Any]))
                } else {
                    continuation.resume(throwing: NSError(domain: "AppleScriptError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]))
                }
            }
        }
    }
    
    class func executeVoid(_ scriptText: String) async throws {
        _ = try await execute(scriptText)
    }

    // macOS auto-launches the target of any Apple event delivered to a
    // non-running app, so a script addressed at Music/Spotify would open it
    // out of nowhere. Every scripted interaction with those apps must go
    // through these gates: if the app is closed, the event is dropped
    // instead of delivered, making an unwanted launch impossible.
    class func isAppRunning(_ bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    @discardableResult
    class func executeIfRunning(_ bundleID: String, _ scriptText: String) async throws -> NSAppleEventDescriptor? {
        guard isAppRunning(bundleID) else { return nil }
        return try await execute(scriptText)
    }

    class func executeVoidIfRunning(_ bundleID: String, _ scriptText: String) async throws {
        _ = try await executeIfRunning(bundleID, scriptText)
    }
}
