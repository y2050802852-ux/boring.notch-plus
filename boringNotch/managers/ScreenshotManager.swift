//
//  ScreenshotManager.swift
//  boringNotch
//
//  1.1.5 region screenshot: a global shortcut dims the screen under the
//  mouse, the user drags out a selection, then fine-tunes it with four edge
//  handles (PPT-style) and confirms with the ✓/✗ buttons (ESC cancels).
//  The PNG lands in the clipboard-history store, goes on the pasteboard as
//  BOTH a file URL and image data — so ⌘V pastes a real file into any
//  Finder folder and the image into chat apps — and the clipboard history
//  records it.
//

import AppKit
import SwiftUI

// MARK: - Manager

@MainActor
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    static func debugLog(_ message: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("boringNotch_screenshot.log").path
        let line = "\(Date()) \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { handle.write(data) }
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @Published var rect: CGRect = .zero
    @Published var adjusting = false

    private var panel: CapturePanel?
    var screenFrame: CGRect = .zero
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var dragStart: CGPoint?
    private var moveOriginRect: CGRect?

    private var overlayID: CGWindowID = 0

    func beginCapture() {
        Self.debugLog("beginCapture preflight=\(CGPreflightScreenCaptureAccess())")
        guard panel == nil else { return }
        // Screen recording permission: without it the capture would silently
        // produce a wallpaper-only image — request access instead.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            return
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main ?? NSScreen.screens.first!
        screenFrame = screen.frame

        let panel = CapturePanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.contentView = NSHostingView(
            rootView: ScreenshotOverlayView(manager: self))
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        overlayID = CGWindowID(panel.windowNumber)

        adjusting = false
        rect = .zero

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            if event.keyCode == 53 { // escape
                self.closeOverlay()
                return nil
            }
            return event
        }
        // Cursor: set deterministically from the pointer position on every
        // mouse event — push/pop stacks corrupt when handles move under a
        // moving pointer (the reported stuck left-right arrows).
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            guard let self, self.panel != nil else { return event }
            let height = self.panel?.frame.height ?? 0
            // Window coords (bottom-left) → view coords (top-left).
            self.updateCursor(
                for: CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y))
            return event
        }
    }

    /// Arrow by default; crosshair near the corner handles; pointing hand
    /// over the ✓/✗ buttons.
    func updateCursor(for viewPoint: CGPoint) {
        guard adjusting else {
            NSCursor.arrow.set()
            return
        }
        for handle in CornerHandle.allCases {
            let p = handle.point(in: rect)
            if abs(viewPoint.x - p.x) <= 14, abs(viewPoint.y - p.y) <= 14 {
                NSCursor.crosshair.set()
                return
            }
        }
        let buttons = confirmButtonsPosition(for: rect)
        if abs(viewPoint.x - buttons.x) <= 44, abs(viewPoint.y - buttons.y) <= 22 {
            NSCursor.pointingHand.set()
            return
        }
        NSCursor.arrow.set()
    }

    // MARK: Gesture callbacks (from the overlay view)

    /// Single entry point for the selecting-phase drag: the first callback
    /// records the corner (events may coalesce — never assume a zero-translation
    /// first event), later ones grow the rect.
    func dragUpdated(to point: CGPoint) {
        guard let start = dragStart else {
            dragStart = point
            adjusting = false
            rect = CGRect(origin: point, size: .zero)
            return
        }
        rect = CGRect(
            x: min(start.x, point.x), y: min(start.y, point.y),
            width: abs(point.x - start.x), height: abs(point.y - start.y))
    }

    func dragEnded() {
        dragStart = nil
        // A click without a meaningful drag is not a selection — abort.
        if rect.width < 10 || rect.height < 10 {
            closeOverlay()
            return
        }
        withAnimation(.smooth(duration: 0.15)) {
            adjusting = true
        }
    }

    func handleDragged(handle: CornerHandle, to point: CGPoint) {
        // The opposite corner anchors; the dragged corner follows the
        // pointer — width and height adjust together. Dragging across the
        // anchor flips the rect; the minimum size keeps it from collapsing.
        let anchor = handle.anchor(in: rect)
        let minimum: CGFloat = 10
        let x = point.x >= anchor.x
            ? max(anchor.x + minimum, point.x)
            : min(anchor.x - minimum, point.x)
        let y = point.y >= anchor.y
            ? max(anchor.y + minimum, point.y)
            : min(anchor.y - minimum, point.y)
        rect = CGRect(
            x: min(anchor.x, x), y: min(anchor.y, y),
            width: abs(x - anchor.x), height: abs(y - anchor.y))
    }

    func selectionDragged(translation: CGSize) {
        // Snapshot the rect at drag start — applying the cumulative
        // translation to the already-moved rect compounds exponentially and
        // makes the frame fly away.
        if moveOriginRect == nil { moveOriginRect = rect }
        guard let origin = moveOriginRect else { return }
        rect = origin.offsetBy(dx: translation.width, dy: translation.height)
    }

    func moveEnded() {
        moveOriginRect = nil
    }

    func captureSelection() {
        let selection = rect
        let frame = screenFrame
        closeOverlay()
        capture(rect: selection, screenFrame: frame)
    }

    func closeOverlay() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        panel?.orderOut(nil)
        panel = nil
        adjusting = false
        rect = .zero
    }

    // MARK: Capture & store

    private func capture(rect: CGRect, screenFrame: CGRect) {
        // The view's top-left-origin rect maps to CG's global top-left space
        // with a vertical offset of (main screen top − this screen top).
        let mainTop = NSScreen.screens.first?.frame.maxY ?? 0
        let cgRect = CGRect(
            x: screenFrame.origin.x + rect.minX,
            y: mainTop - screenFrame.maxY + rect.minY,
            width: rect.width,
            height: rect.height)

        // The overlay window sits above everything; capturing only the
        // windows below it excludes the dimming layer from the image.
        guard let image = CGWindowListCreateImage(
            cgRect, [.optionOnScreenBelowWindow], overlayID,
            [.bestResolution]) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }

        // Store the PNG in the clipboard store under a friendly name —
        // pasting into a Finder folder copies this file out.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = "截图-\(formatter.string(from: Date())).png"
        let storeURL = ClipboardManager.storeDirectory
            .appendingPathComponent(file)
        do {
            try FileManager.default.createDirectory(
                at: ClipboardManager.storeDirectory, withIntermediateDirectories: true)
            try png.write(to: storeURL)
        } catch {
            Self.debugLog("screenshot save failed: \(error.localizedDescription)")
            return
        }
        ClipboardManager.shared.recordImageFile(file)

        // Pasteboard carries BOTH a file reference and the image data:
        // ⌘V in a Finder folder pastes the file; ⌘V in a chat app pastes
        // the image.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([storeURL as NSURL])
        pasteboard.setData(png, forType: .png)
        ClipboardManager.shared.suppressNextCapture()
    }

    func imageWidthLabel() -> String {
        "\(Int(rect.width)) × \(Int(rect.height))"
    }

    /// Confirms/cancels button pair position: the selection's bottom-right
    /// corner, clamped to the screen.
    func confirmButtonsPosition(for rect: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(rect.maxX - 8, 80), screenFrame.maxX - 90),
            y: min(rect.maxY + 30, screenFrame.maxY - 40))
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Handles

enum CornerHandle: CaseIterable {
    case topLeft, topTrailing, bottomLeading, bottomTrailing

    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topTrailing: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeading: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomTrailing: return CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// The corner that stays fixed while this handle drags.
    func anchor(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .topTrailing: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomLeading: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomTrailing: return CGPoint(x: rect.minX, y: rect.minY)
        }
    }
}

// MARK: - Overlay view

struct ScreenshotOverlayView: View {
    @ObservedObject var manager: ScreenshotManager

    var body: some View {
        ZStack {
            // Dimming with a transparent hole at the selection. VISUAL ONLY —
            // gestures never attach to the masked view (the mask breaks
            // SwiftUI hit-testing and swallows every mouse event).
            Color.black.opacity(0.35)
                .inverseMask(selectionHole)
                .ignoresSafeArea()

            selectionBorder

            // Full-screen interaction layer ABOVE the dimming: receives all
            // mouse events deterministically (no mask in its hit path).
            Color.clear
                .contentShape(Rectangle())
                .gesture(interactionGesture)

            if manager.adjusting {
                selectionHandles
                confirmButtons
            }
        }
    }

    private var interactionGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if manager.adjusting {
                    // Adjusting: dragging inside the selection moves it.
                    guard manager.rect.contains(value.startLocation) else { return }
                    manager.selectionDragged(translation: value.translation)
                } else {
                    manager.dragUpdated(to: value.location)
                }
            }
            .onEnded { _ in
                if manager.adjusting { manager.moveEnded() }
                else { manager.dragEnded() }
            }
    }

    private var selectionHole: some View {
        Rectangle()
            .frame(width: max(0, manager.rect.width), height: max(0, manager.rect.height))
            .position(x: manager.rect.midX, y: manager.rect.midY)
    }

    private var selectionBorder: some View {
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 1.5)
            .background(
                Rectangle().strokeBorder(Color.black.opacity(0.4), lineWidth: 0.5)
            )
            .frame(width: max(0, manager.rect.width), height: max(0, manager.rect.height))
            .position(x: manager.rect.midX, y: manager.rect.midY)
            .overlay(alignment: .bottom) {
                if manager.adjusting {
                    Text(manager.imageWidthLabel())
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .offset(y: 16)
                        .allowsHitTesting(false)
                }
            }
    }

    /// ✓ capture / ✗ cancel, at the selection's bottom-right corner.
    private var confirmButtons: some View {
        let position = manager.confirmButtonsPosition(for: manager.rect)
        return HStack(spacing: 12) {
            Button {
                manager.captureSelection()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .help("Capture")

            Button {
                manager.closeOverlay()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.gray.opacity(0.9)))
            }
            .buttonStyle(.plain)
            .help("Cancel")
        }
        .position(position)
    }

    private var selectionHandles: some View {
        ForEach(Array(CornerHandle.allCases.enumerated()), id: \.element) { _, handle in
            CornerView(handle: handle, manager: manager)
        }
    }
}

private struct CornerView: View {
    let handle: CornerHandle
    @ObservedObject var manager: ScreenshotManager

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.accentColor, lineWidth: 2))
            .shadow(radius: 1)
            .position(handle.point(in: manager.rect))
            .onHover { hovering in
                NSCursor.crosshair.set()
                if !hovering { NSCursor.arrow.set() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        manager.handleDragged(handle: handle, to: value.location)
                    }
            )
    }
}

// MARK: - Helpers

extension View {
    /// Inverts the given shape mask (used to dim everything but the hole).
    @ViewBuilder
    func inverseMask<Mask: View>(_ mask: Mask) -> some View {
        self.mask {
            Rectangle().overlay(mask.foregroundStyle(.white).blendMode(.destinationOut))
        }
    }
}
