//
//  NotificationInterceptor.swift
//  boringNotch
//
//  1.1.0 notification interception: observes the system Notification Center
//  process over the Accessibility API, transcribes banner content into the
//  notch (sneak-peek + history list) and hides the original banner so the
//  system HUD never shows. Feasibility verified on macOS 26 (see spike:
//  banners appear as AXNotificationCenterBanner elements inside an
//  AXWindow/AXSystemDialog "Notification Center" window; the window's
//  kAXPositionAttribute is settable, so banners can be hidden off-screen
//  while staying in the Notification Center list).
//

import ApplicationServices
import AppKit
import Defaults
import SwiftUI

struct NotificationRecord: Identifiable, Equatable {
    let id = UUID()
    let appName: String
    let title: String
    let subtitle: String
    let body: String
    let date: Date
}

@MainActor
final class NotificationInterceptor: ObservableObject {
    static let shared = NotificationInterceptor()

    @Published var displayedNotification: NotificationRecord?
    @Published private(set) var recentNotifications: [NotificationRecord] = []
    @Published private(set) var accessibilityGranted: Bool = false

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var scanTimer: Timer?
    private var seenBannerKeys: [String: Date] = [:]
    private var hideWorkItem: DispatchWorkItem?
    private var running = false
    private var hostPresent = false
    private var retryTimer: Timer?

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateRunning()
            }
        }
        updateRunning()
        // Ad-hoc builds lose the accessibility grant on every reinstall;
        // poll for it so the interceptor arms itself automatically (within
        // 5s) as soon as the user re-grants.
        if retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, !self.running else { return }
                    self.updateRunning()
                }
            }
        }
    }

    /// File-based trace: NSLog is not reliably visible via `log show` in this
    /// environment, and the app is sandboxed — so the trace goes to the
    /// container's temporary directory (readable from the terminal).
    private static func debugLog(_ message: String) {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("boringNotch_notifications.log").path
        let line = "\(Date()) \(message)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) { handle.write(data) }
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    func updateRunning() {
        let toggle = Defaults[.notificationInterceptor]
        let trusted = AXIsProcessTrusted()
        accessibilityGranted = trusted
        let stdDirect = UserDefaults.standard.bool(forKey: "notificationInterceptor")
        Self.debugLog(
            "updateRunning bundle=\(Bundle.main.bundleIdentifier) uid=\(getuid()) "
                + "toggle=\(toggle) stdDirect=\(stdDirect) axTrusted=\(trusted) running=\(running) "
                + "tmpDir=\(FileManager.default.temporaryDirectory.path)"
        )
        let shouldRun = toggle && trusted
        if shouldRun && !running {
            start()
        } else if !shouldRun && running {
            stop()
        }
    }

    private func start() {
        Self.debugLog("start: called (running=\(running))")
        guard !running else { return }
        guard let nc = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        }), nc.processIdentifier != 0 else {
            Self.debugLog("start: NotificationCenter process not found")
            return
        }
        Self.debugLog("start: NC pid=\(nc.processIdentifier)")

        appElement = AXUIElementCreateApplication(nc.processIdentifier)
        guard let appElement else {
            Self.debugLog("start: appElement nil")
            return
        }

        var obs: AXObserver?
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let createResult = AXObserverCreate(nc.processIdentifier, { observer, element, notification, refcon in
            guard let refcon else { return }
            let interceptor = Unmanaged<NotificationInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            let elementCopy = element
            let name = notification as String
            Task { @MainActor in
                interceptor.handleAXEvent(element: elementCopy, notification: name)
            }
        }, &obs)
        if createResult == .success, let observer = obs {
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            let addResult = AXObserverAddNotification(
                observer,
                appElement,
                kAXWindowCreatedNotification as CFString,
                refcon
            )
            Self.debugLog("start: AXObserver ready (add err=\(addResult.rawValue))")
            self.observer = observer
        } else {
            // The observer is only an accelerator; polling alone still works
            // (and may be the only option from inside the sandbox).
            Self.debugLog("start: AXObserver unavailable (err=\(createResult.rawValue)), poll-only")
        }

        // Persistent poll while enabled — the base mechanism. The observer,
        // when usable, accelerates the first response via handleAXEvent.
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanTick()
            }
        }
        running = true
        Self.debugLog("start: RUNNING (pid=\(nc.processIdentifier))")
    }

    func stop() {
        guard running else { return }
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        scanTimer?.invalidate()
        scanTimer = nil
        seenBannerKeys.removeAll()
        displayedNotification = nil
        running = false
        NSLog("📢 NotificationInterceptor: stopped")
    }

    // MARK: - AX events

    private func handleAXEvent(element: AXUIElement, notification: String) {
        guard running, Defaults[.notificationInterceptor] else { return }
        // Event-driven fast path: scan the delivered element right away (the
        // poll tick is the slower safety net).
        scanBanners(in: element)
    }

    private func findBannerHost() -> AXUIElement? {
        guard let nc = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.notificationcenterui"
        }), nc.processIdentifier != 0 else { return nil }
        let app = AXUIElementCreateApplication(nc.processIdentifier)
        return axList(app, kAXWindowsAttribute).first { w in
            (axStr(w, kAXSubroleAttribute) ?? "") == "AXSystemDialog"
                && (axStr(w, kAXTitleAttribute) ?? "") == "Notification Center"
        }
    }

    private func scanTick() {
        guard running, Defaults[.notificationInterceptor] else {
            stop()
            return
        }
        guard let host = findBannerHost() else {
            if hostPresent {
                hostPresent = false
                Self.debugLog("tick: banner host gone")
            }
            return
        }
        if !hostPresent {
            hostPresent = true
            Self.debugLog("tick: banner host APPEARED")
        }
        scanBanners(in: host)
    }

    private func scanBanners(in window: AXUIElement) {
        var banners: [AXUIElement] = []
        collectBanners(window, into: &banners, depth: 0)
        var hostHidden = false
        for banner in banners {
            guard let record = extractRecord(from: banner) else { continue }
            let key = "\(record.appName)|\(record.title)|\(record.subtitle)|\(record.body)"
            if let seen = seenBannerKeys[key], Date().timeIntervalSince(seen) < 10 {
                continue
            }
            seenBannerKeys[key] = Date()
            Self.debugLog("new notification: app=\(record.appName) title=\(record.title)")
            // prune stale keys
            seenBannerKeys = seenBannerKeys.filter { Date().timeIntervalSince($0.value) < 60 }
            if !hostHidden {
                Self.debugLog("scan: hiding banner window (mode=\(Defaults[.notificationHideOffScreen] ? "offScreen" : "close"))")
                hideBannerWindowIfNeeded(window)
                hostHidden = true
            }
            display(record)
        }
    }

    private func hideBannerWindowIfNeeded(_ window: AXUIElement) {
        guard Defaults[.notificationHideOriginal] else { return }
        if Defaults[.notificationHideOffScreen] {
            var target = CGPoint(x: -2000, y: -2000)
            guard let value = AXValueCreate(.cgPoint, &target) else { return }
            let err = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
            NSLog("📢 NotificationInterceptor: hide (off-screen) err=\(err.rawValue)")
        } else {
            // close mode: press the localized close action on each banner
            var banners: [AXUIElement] = []
            collectBanners(window, into: &banners, depth: 0)
            for banner in banners {
                let names = axActions(banner)
                guard let closeName = names.first(where: { $0.contains("关闭") || $0.contains("Close") }) else { continue }
                AXUIElementPerformAction(banner, closeName as CFString)
            }
        }
    }

    // MARK: - Extraction

    private func collectBanners(_ el: AXUIElement, into out: inout [AXUIElement], depth: Int) {
        guard depth < 12 else { return }
        if (axStr(el, kAXSubroleAttribute) ?? "") == "AXNotificationCenterBanner" {
            out.append(el)
        }
        for child in axList(el, kAXChildrenAttribute) {
            collectBanners(child, into: &out, depth: depth + 1)
        }
    }

    private func collectTexts(_ el: AXUIElement, into out: inout [String], depth: Int) {
        guard depth < 12 else { return }
        if (axStr(el, kAXRoleAttribute) ?? "") == "AXStaticText" {
            if let v = axStr(el, kAXValueAttribute), !v.isEmpty { out.append(v) }
        }
        for child in axList(el, kAXChildrenAttribute) {
            collectTexts(child, into: &out, depth: depth + 1)
        }
    }

    private func extractRecord(from banner: AXUIElement) -> NotificationRecord? {
        let desc = axStr(banner, kAXDescriptionAttribute) ?? ""
        var texts: [String] = []
        collectTexts(banner, into: &texts, depth: 0)
        guard !texts.isEmpty else { return nil }

        let title = texts[0]
        let subtitle = texts.count >= 3 ? texts[1] : ""
        let body = texts.count >= 3 ? texts[2] : (texts.count == 2 ? texts[1] : "")
        guard !title.isEmpty || !body.isEmpty else { return nil }

        // desc = "<AppName> <Title>, <Subtitle>, <Body>" — recover the app
        // name by stripping the title off the front of the description.
        var appName = ""
        if !title.isEmpty, let range = desc.range(of: title) {
            appName = String(desc[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        if appName.isEmpty { appName = "通知" }

        Self.debugLog("extract: texts=\(texts) appName=\(appName)")
        return NotificationRecord(appName: appName, title: title, subtitle: subtitle, body: body, date: Date())
    }

    // MARK: - Display

    private func display(_ record: NotificationRecord) {
        recentNotifications.insert(record, at: 0)
        let limit = max(5, Defaults[.notificationHistoryLimit])
        if recentNotifications.count > limit {
            recentNotifications.removeLast(recentNotifications.count - limit)
        }
        withAnimation(.smooth(duration: 0.3)) {
            displayedNotification = record
        }
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.smooth(duration: 0.3)) {
                self?.displayedNotification = nil
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + max(2, Defaults[.notificationDisplayDuration]),
            execute: work
        )
    }

    func clearHistory() {
        recentNotifications.removeAll()
    }
}

// MARK: - AX helpers (nonisolated)

private func axStr(_ el: AXUIElement, _ name: String) -> String? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v as? String
}

private func axList(_ el: AXUIElement, _ name: String) -> [AXUIElement] {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success,
          let arr = v as? [AXUIElement] else { return [] }
    return arr
}

private func axActions(_ el: AXUIElement) -> [String] {
    var v: CFArray?
    guard AXUIElementCopyActionNames(el, &v) == .success, let arr = v as? [String] else { return [] }
    return arr
}
