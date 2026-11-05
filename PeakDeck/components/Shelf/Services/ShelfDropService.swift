//
//  ShelfDropService.swift
//  PeakDeck
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

struct ShelfDropService {
    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }

    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        Logger.log("ShelfDrop: processing provider \(provider.registeredTypeIdentifiers)", category: .debug)

        if let actualFileURL = await provider.extractFileURL() {
            Logger.log("ShelfDrop: file URL extracted: \(actualFileURL.path)", category: .debug)
            if let item = await fileItem(for: actualFileURL, temporary: false) {
                return item
            }
            Logger.log("ShelfDrop: bookmark failed for \(actualFileURL.path); trying fallbacks", category: .warning)
        } else {
            Logger.log("ShelfDrop: no file URL representation", category: .debug)
        }

        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let item = await fileItem(for: url, temporary: false) {
                    return item
                }
                Logger.log("ShelfDrop: bookmark failed for URL \(url.path); trying fallbacks", category: .warning)
            } else {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
        } else {
            Logger.log("ShelfDrop: no URL representation", category: .debug)
        }

        if let text = await provider.extractText() {
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }

        if let data = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            Logger.log("ShelfDrop: failed to store loaded data (\(data.count) bytes)", category: .error)
        }

        if let fileURL = await provider.extractItem() {
            Logger.log("ShelfDrop: generic item extracted: \(fileURL.path)", category: .debug)
            if let item = await fileItem(for: fileURL, temporary: false) {
                return item
            }
        }

        Logger.log("ShelfDrop: provider could not be converted to a shelf item", category: .error)
        return nil
    }

    private static func fileItem(for url: URL, temporary: Bool) async -> ShelfItem? {
        guard let bookmark = createBookmark(for: url) else { return nil }
        return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: temporary)
    }

    private static func createBookmark(for url: URL) -> Data? {
        do {
            return try Bookmark(url: url).data
        } catch {
            Logger.log("ShelfDrop: bookmark creation failed for \(url.path): \(error.localizedDescription)", category: .error)
            return nil
        }
    }
}

