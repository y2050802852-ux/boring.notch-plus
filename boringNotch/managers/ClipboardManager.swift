//
//  ClipboardManager.swift
//  boringNotch
//
//  1.1.2 clipboard history: polls NSPasteboard.changeCount (no public
//  change notification exists on macOS), captures text and images, skips
//  password-manager copies (org.nspasteboard.ConcealedType) and persists
//  to the app's Application Support directory so history survives relaunch.
//

import AppKit
import Defaults
import SwiftUI

// MARK: - Model

struct ClipboardItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case text
        case image
    }

    let id: UUID
    let kind: Kind
    let text: String?
    let imageFile: String?
    let date: Date
}

// MARK: - Manager

@MainActor
final class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()

    @Published private(set) var items: [ClipboardItem] = []

    private var timer: Timer?
    private var lastChangeCount: Int = 0
    private var imageCache: [UUID: NSImage] = [:]

    private let maxTextLength = 500_000
    private let maxImageBytes = 25 * 1024 * 1024

    private static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("boringNotch/clipboard", isDirectory: true)
    }

    private static var manifestURL: URL {
        storeDirectory.appendingPathComponent("items.json")
    }

    private init() {
        load()
        // Baseline: never capture whatever was on the clipboard before launch.
        lastChangeCount = NSPasteboard.general.changeCount
        updateRunning()
    }

    func updateRunning() {
        if Defaults[.clipboardHistoryEnabled] {
            start()
        } else {
            stop()
        }
    }

    private func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let changeCount = NSPasteboard.general.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        capture()
    }

    // MARK: Capture

    private func capture() {
        let pasteboard = NSPasteboard.general
        let typeNames = (pasteboard.types ?? []).map(\.rawValue)

        // Password managers (1Password, Bitwarden, …) mark sensitive copies
        // with this marker — never record them.
        if typeNames.contains(where: { $0 == "org.nspasteboard.ConcealedType" }) {
            return
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            add(ClipboardItem(
                id: UUID(), kind: .text,
                text: String(text.prefix(maxTextLength)), imageFile: nil, date: Date()))
            return
        }

        if let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
           let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]),
           png.count <= maxImageBytes {
            let file = "img-\(UUID().uuidString).png"
            let url = Self.storeDirectory.appendingPathComponent(file)
            do {
                try FileManager.default.createDirectory(at: Self.storeDirectory, withIntermediateDirectories: true)
                try png.write(to: url)
            } catch {
                Self.debugLog("clipboard: image write failed \(error.localizedDescription)")
                return
            }
            add(ClipboardItem(id: UUID(), kind: .image, text: nil, imageFile: file, date: Date()))
        }
    }

    private func add(_ item: ClipboardItem) {
        // Same content recopied: move to top with a fresh date instead of
        // duplicating.
        if let index = items.firstIndex(where: {
            $0.kind == item.kind && $0.text == item.text && $0.imageFile == nil
        }) {
            var existing = items.remove(at: index)
            existing = ClipboardItem(
                id: existing.id, kind: existing.kind, text: existing.text,
                imageFile: existing.imageFile, date: item.date)
            items.insert(existing, at: 0)
            save()
            return
        }
        items.insert(item, at: 0)
        trimToLimit()
        save()
    }

    private func trimToLimit() {
        let limit = max(5, Defaults[.clipboardHistoryLimit])
        while items.count > limit {
            let removed = items.removeLast()
            if let file = removed.imageFile {
                try? FileManager.default.removeItem(at: Self.storeDirectory.appendingPathComponent(file))
                imageCache.removeValue(forKey: removed.id)
            }
        }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.manifestURL),
              var loaded = try? JSONDecoder().decode([ClipboardItem].self, from: data) else { return }
        // Drop image entries whose file vanished (user cleared the folder).
        loaded = loaded.filter { item in
            guard let file = item.imageFile else { return true }
            return FileManager.default.fileExists(
                atPath: Self.storeDirectory.appendingPathComponent(file).path)
        }
        items = loaded
    }

    private func save() {
        trimToLimit()
        do {
            try FileManager.default.createDirectory(at: Self.storeDirectory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(items)
            try data.write(to: Self.manifestURL, options: .atomic)
        } catch {
            Self.debugLog("clipboard: save failed \(error.localizedDescription)")
        }
    }

    // MARK: Actions

    func copyToClipboard(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .image:
            if let data = try? Data(contentsOf: Self.storeDirectory.appendingPathComponent(item.imageFile ?? "")) {
                pasteboard.setData(data, forType: .png)
            }
        }
        // Our own write must not be captured as a new copy.
        lastChangeCount = pasteboard.changeCount
    }

    func image(for item: ClipboardItem) -> NSImage? {
        guard item.kind == .image, let file = item.imageFile else { return nil }
        if let cached = imageCache[item.id] { return cached }
        let image = NSImage(contentsOf: Self.storeDirectory.appendingPathComponent(file))
        if let image { imageCache[item.id] = image }
        return image
    }

    func clearAll() {
        for item in items where item.imageFile != nil {
            try? FileManager.default.removeItem(
                at: Self.storeDirectory.appendingPathComponent(item.imageFile ?? ""))
        }
        imageCache.removeAll()
        items.removeAll()
        save()
    }

    private static func debugLog(_ message: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("boringNotch_clipboard.log").path
        let line = "\(Date()) \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { handle.write(data) }
        }
    }
}

// MARK: - Notch tab panel

struct ClipboardHistoryView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var clipboard = ClipboardManager.shared
    @State private var copiedID: UUID?
    @State private var haptics: Bool = false

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !clipboard.items.isEmpty {
                    HoverButton(icon: "trash", iconColor: .gray) {
                        clipboard.clearAll()
                    }
                    .help("Clear clipboard history")
                }
            }

            if clipboard.items.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "doc.on.clipboard")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    Text("No clipboard history yet")
                        .foregroundStyle(.gray)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                    Text("Copy anything and it shows up here")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(clipboard.items) { item in
                            row(for: item)
                                .padding(8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.horizontal, 6)
        // Scrolling the history must never feed the swipe-up-to-close gesture.
        .onHover { hovering in
            vm.isHoveringScrollableContent = hovering
        }
        .sensoryFeedback(.alignment, trigger: haptics)
    }

    private func row(for item: ClipboardItem) -> some View {
        let isCopied = copiedID == item.id
        return Button {
            clipboard.copyToClipboard(item)
            if Defaults[.enableHaptics] { haptics.toggle() }
            withAnimation(.smooth(duration: 0.2)) { copiedID = item.id }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedID == item.id {
                    withAnimation(.smooth(duration: 0.2)) { copiedID = nil }
                }
            }
        } label: {
            HStack(spacing: 10) {
                rowContent(for: item)
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.clipboard")
                        .font(.system(size: 11))
                        .foregroundStyle(isCopied ? Color.effectiveAccent : Color(white: 0.45))
                    Text(item.date, style: .time)
                        .font(.system(size: 9))
                        .foregroundStyle(.gray)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isCopied ? "Copied" : "Copy to clipboard")
    }

    @ViewBuilder
    private func rowContent(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .text:
            Text(item.text ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .image:
            if let image = clipboard.image(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 48)
                    .cornerRadius(6)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.gray)
            }
        }
    }
}
