//
//  NSItemProvider+LoadHelpers.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

/// Result of a provider item load; `item` is whatever the provider handed
/// back (URL, Data, String, …).
private struct LoadedItem {
    let item: Any?
    let error: Error?
}

extension NSItemProvider {

    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }


    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }

    /// Loads raw data for the given type identifier
    func loadData() async -> Data? {
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { item, error in
                if let error = error {
                    Logger.log("Error loading data for type \(UTType.data.identifier): \(error.localizedDescription)", category: .error)
                    cont.resume(returning: nil)
                    return
                }
                if let url = item as? URL {
                    // SwiftUI materializes promised drops as placeholder files
                    // under this marker path; real file URLs must NOT be read
                    // into memory (a 2 GB file would be loaded just to be
                    // discarded), so check the marker before touching contents.
                    let isPromisePlaceholder = url.absoluteString.contains("com.apple.SwiftUI.filePromises")
                    if !isPromisePlaceholder {
                        Logger.log("loadData: non-promise file URL \(url.path); skipping data load", category: .debug)
                        cont.resume(returning: nil)
                        return
                    }
                    let data = try? Data(contentsOf: url)
                    self.suggestedName = self.suggestedName ?? url.lastPathComponent

                    let fileManager = FileManager.default
                    let folderURL = url.deletingLastPathComponent()

                    do {
                        // Delete the file first
                        try fileManager.removeItem(at: url)
                        Logger.log("Deleted promise placeholder: \(url.path)", category: .debug)

                        // Check folder contents
                        let contents = try fileManager.contentsOfDirectory(atPath: folderURL.path)
                        if contents.isEmpty {
                            try fileManager.removeItem(at: folderURL)
                            Logger.log("Folder was empty, deleted folder: \(folderURL.path)", category: .debug)
                        } else {
                            Logger.log("Folder not deleted — it still contains \(contents.count) item(s).", category: .debug)
                        }

                    } catch {
                        Logger.log("Error cleaning promise placeholder: \(error.localizedDescription)", category: .error)
                    }

                    cont.resume(returning: data)
                } else if let data = item as? Data {
                    cont.resume(returning: data)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if self.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                //Validate URL
                guard url.scheme != nil else { return nil }
                return url
            }
        }

        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads an item with a hard timeout. A provider that never calls its
    /// completion (observed with large drags) would otherwise hang the
    /// whole drop pipeline forever with no feedback.
    private func loadItemWithTimeout(
        forTypeIdentifier typeIdentifier: String,
        timeout: TimeInterval = 10
    ) async -> LoadedItem? {
        await withCheckedContinuation { (cont: CheckedContinuation<LoadedItem?, Never>) in
            let lock = NSLock()
            var finished = false
            let timeoutItem = DispatchWorkItem {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                Logger.log("loadItem timed out after \(timeout)s for type \(typeIdentifier)", category: .warning)
                cont.resume(returning: nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout, execute: timeoutItem)
            self.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                timeoutItem.cancel()
                cont.resume(returning: LoadedItem(item: item, error: error))
            }
        }
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        guard let result = await loadItemWithTimeout(forTypeIdentifier: typeIdentifier) else {
            return nil
        }
        if let error = result.error {
            Logger.log("Error loading item for type \(typeIdentifier): \(error.localizedDescription)", category: .error)
            return nil
        }
        let item = result.item
        var resolvedURL: URL?
        if let url = item as? URL {
            // Direct URL provided
            resolvedURL = url
        } else if let data = item as? Data {
            // Some providers hand out a UTF-8 file URL string, others a bookmark. Prefer parsing string first.
            if let string = String(data: data, encoding: .utf8) {
                if let url = URL(string: string) {
                    resolvedURL = url
                } else if string.hasPrefix("/") {
                    // Plain file system path
                    resolvedURL = URL(fileURLWithPath: string)
                }
            }
            if resolvedURL == nil {
                // Fallback: try treating the data as a bookmark
                let bookmark = Bookmark(data: data)
                resolvedURL = bookmark.resolveURL()
            }
        } else if let string = item as? String {
            if let url = URL(string: string) {
                resolvedURL = url
            } else if string.hasPrefix("/") {
                resolvedURL = URL(fileURLWithPath: string)
            }
        }
        if resolvedURL == nil {
            Logger.log("loadFileURL: unhandled item type \(type(of: item)) for \(typeIdentifier)", category: .warning)
        }
        return resolvedURL
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        guard let result = await loadItemWithTimeout(forTypeIdentifier: typeIdentifier) else {
            return nil
        }
        if result.error != nil {
            return nil
        }
        let item = result.item

        if let url = item as? URL {
            return url
        } else if let data = item as? Data {
            if let string = String(data: data, encoding: .utf8) {
                if let url = URL(string: string) {
                    return url
                } else if string.hasPrefix("/") {
                    return URL(fileURLWithPath: string)
                }
            }
            return nil
        } else if let string = item as? String {
            if let url = URL(string: string) {
                return url
            } else if string.hasPrefix("/") {
                return URL(fileURLWithPath: string)
            }
            return nil
        }
        return nil
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        guard let result = await loadItemWithTimeout(forTypeIdentifier: typeIdentifier) else {
            return nil
        }
        if result.error != nil {
            return nil
        }
        let item = result.item

        if let string = item as? String {
            return string
        } else if let data = item as? Data,
                  let string = String(data: data, encoding: .utf8) {
            return string
        }
        return nil
    }
}
