//
//  ScreenshotManager.swift
//  boringNotch
//
//  1.1.5 region screenshot: a global shortcut dims the screen under the
//  mouse, the user drags out a selection, then fine-tunes it with four edge
//  handles (PPT-style) and captures with Enter/double-click (ESC cancels).
//  The PNG is saved to the Desktop, put on the pasteboard — the clipboard
//  history polling then picks it up automatically.
//

import AppKit
import SwiftUI

// MARK: - Manager

@MainActor
final class ScreenshotManager: ObservableObject {
    static let shared = ScreenshotManager()

    @Published var rect: CGRect = .zero
    @Published var adjusting = false

    private var panel: CapturePanel?
    private var screenFrame: CGRect = .zero
    private var keyMonitor: Any?
    private var dragStart: CGPoint?

    private var overlayID: CGWindowID = 0

    func beginCapture() {
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
            switch event.keyCode {
            case 36, 76: // return / keypad enter
                if self.adjusting { self.captureSelection() }
                return nil
            case 53: // escape
                self.closeOverlay()
                return nil
            default:
                return event
            }
        }
    }

    // MARK: Gesture callbacks (from the overlay view)

    func dragStarted(at point: CGPoint) {
        dragStart = point
        adjusting = false
        rect = CGRect(origin: point, size: .zero)
    }

    func dragChanged(to point: CGPoint) {
        guard let start = dragStart else { return }
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

    func handleDragged(handle: EdgeHandle, to point: CGPoint) {
        var r = rect
        let minimum: CGFloat = 10
        switch handle {
        case .top:
            r = CGRect(
                x: r.minX, y: min(point.y, r.maxY - minimum),
                width: r.width, height: max(minimum, r.maxY - point.y))
        case .bottom:
            r = CGRect(
                x: r.minX, y: r.minY,
                width: r.width, height: max(minimum, point.y - r.minY))
        case .leading:
            r = CGRect(
                x: min(point.x, r.maxX - minimum), y: r.minY,
                width: max(minimum, r.maxX - point.x), height: r.height)
        case .trailing:
            r = CGRect(
                x: r.minX, y: r.minY,
                width: max(minimum, point.x - r.minX), height: r.height)
        }
        rect = r
    }

    func selectionDragged(translation: CGSize) {
        guard adjusting else { return }
        rect = rect.offsetBy(dx: translation.width, dy: translation.height)
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
        panel?.orderOut(nil)
        panel = nil
        adjusting = false
        rect = .zero
    }

    // MARK: Capture & save

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

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/截图-\(formatter.string(from: Date())).png")
        try? png.write(to: url)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        // The clipboard history polling picks this pasteboard change up and
        // files the screenshot automatically.
    }

    func imageWidthLabel() -> String {
        "\(Int(rect.width)) × \(Int(rect.height))"
    }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - Handles

enum EdgeHandle: CaseIterable {
    case top, bottom, leading, trailing

    /// Midpoint of this edge inside `rect`.
    func point(in rect: CGRect) -> CGPoint {
        switch self {
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .leading: return CGPoint(x: rect.minX, y: rect.midY)
        case .trailing: return CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    var cursor: NSCursor {
        switch self {
        case .top, .bottom: return .resizeUpDown
        case .leading, .trailing: return .resizeLeftRight
        }
    }
}

// MARK: - Overlay view

struct ScreenshotOverlayView: View {
    @ObservedObject var manager: ScreenshotManager

    var body: some View {
        ZStack {
            // Dimming with a transparent hole at the selection: four bands
            // around the rect.
            Color.black.opacity(0.35)
                .inverseMask(selectionHole)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .gesture(selectDragGesture)

            selectionBorder

            if manager.adjusting {
                selectionHandles
            }
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
            .contentShape(Rectangle())
            .gesture(manager.adjusting ? moveGesture : nil)
            .onTapGesture(count: 2) {
                if manager.adjusting { manager.captureSelection() }
            }

            // Size badge while adjusting, PPT-style.
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

    private var selectionHandles: some View {
        ForEach(Array(EdgeHandle.allCases.enumerated()), id: \.element) { _, handle in
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
                .shadow(radius: 1)
                .position(handle.point(in: manager.rect))
                .cursor(handle.cursor)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            manager.handleDragged(handle: handle, to: value.location)
                        }
                )
        }
    }

    private var selectDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if value.translation == .zero {
                    manager.dragStarted(at: value.location)
                } else {
                    manager.dragChanged(to: value.location)
                }
            }
            .onEnded { _ in manager.dragEnded() }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                manager.selectionDragged(translation: value.translation)
            }
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

    @ViewBuilder
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { _ in cursor.push() }
    }
}
