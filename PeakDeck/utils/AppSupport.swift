//
//  AppSupport.swift
//  PeakDeck
//

import Foundation

/// Root of the app's Application Support data (shelf, clipboard history).
/// Moves the legacy `boringNotch` folder into `PeakDeck` exactly once so
/// history survives the project rename.
enum AppSupport {
    private static let migrationLock = NSLock()

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let new = base.appendingPathComponent("PeakDeck", isDirectory: true)
        let old = base.appendingPathComponent("boringNotch", isDirectory: true)
        let fm = FileManager.default

        migrationLock.lock()
        defer { migrationLock.unlock() }
        if !fm.fileExists(atPath: new.path) {
            if fm.fileExists(atPath: old.path) {
                try? fm.createDirectory(at: base, withIntermediateDirectories: true)
                try? fm.moveItem(at: old, to: new)
            } else {
                try? fm.createDirectory(at: new, withIntermediateDirectories: true)
            }
        }
        return new
    }
}
