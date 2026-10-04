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

/// One pressable button of an intercepted system alert (the AX element is
/// retained so the notch can trigger the real action later).
struct AlertButton {
    let label: String
    let element: AXUIElement
}

/// An intercepted system alert (alarm/timer/legacy popups). The notch shows
/// the alert's own buttons; pressing one performs the real AXPress on the
/// (hidden) system alert. `window` is the hideable window; `trackElement`
/// identifies the alert itself for liveness checks (they differ for alerts
/// living inside the shared Notification Center host window).
struct PendingAlert: Identifiable {
    let id = UUID()
    let appName: String
    let title: String
    let message: String
    let window: AXUIElement
    let trackElement: AXUIElement
    let isHostAlert: Bool
    let originalPosition: CGPoint
    var buttons: [AlertButton]
}

@MainActor
final class NotificationInterceptor: ObservableObject {
    static let shared = NotificationInterceptor()

    @Published var displayedNotification: NotificationRecord?
    @Published var displayedAlert: PendingAlert?
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

    // UserNotificationCenter watch (alarm/timer/legacy alerts)
    private var uncTimer: Timer?
    private var uncSeenWindows: [CFHashCode: Date] = [:]
    // Windows we hid off-screen, with their original positions, so stop()
    // can bring them back and nothing is lost when interception turns off.
    private var uncHidden: [CFHashCode: (window: AXUIElement, original: CGPoint)] = [:]

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
        startUNCWatch()
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
        stopUNCWatch()
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
            if Self.isMuted(record.appName) {
                Self.debugLog("muted app: history only, no sneak peek")
                recordInHistory(record)
            } else {
                display(record)
            }
        }

        // Alarm/timer alerts live inside this same Notification Center host
        // window but are NOT AXNotificationCenterBanner elements — scan for
        // them when no banner is present.
        if banners.isEmpty {
            scanHostAlert(in: window)
        }
    }

    // MARK: - Alarm alerts inside the Notification Center host window

    /// Alarm/timer alerts share the banner host window; find alert-shaped
    /// containers (a button's top ancestor below the host) and intercept the
    /// alarm-like ones.
    private func scanHostAlert(in host: AXUIElement) {
        let buttonEls = collectRoleElements(host, role: "AXButton", depth: 0)

        var containers: [AXUIElement] = []
        var seenContainerHashes: Set<CFHashCode> = []
        for button in buttonEls {
            guard let container = topAncestorBelow(button, root: host) else { continue }
            let hash = CFHash(container)
            if !seenContainerHashes.contains(hash) {
                seenContainerHashes.insert(hash)
                containers.append(container)
            }
        }

        for container in containers {
            let hash = CFHash(container)
            // Already showing this exact alert — it stays ringing for minutes.
            if let current = displayedAlert, CFHash(current.trackElement) == hash { return }
            if let seen = uncSeenWindows[hash], Date().timeIntervalSince(seen) < 600 { continue }
            uncSeenWindows[hash] = Date()

            var texts: [String] = []
            collectTexts(container, into: &texts, depth: 0)
            let cbtns = collectRoleElements(container, role: "AXButton", depth: 0)
            let buttons: [AlertButton] = cbtns.compactMap { el in
                guard let label = axStr(el, kAXTitleAttribute) ?? axStr(el, kAXDescriptionAttribute),
                      !label.isEmpty else { return nil }
                return AlertButton(label: label, element: el)
            }
            guard !texts.isEmpty, !buttons.isEmpty else { continue }

            Self.debugLog(
                "NC host alert candidate: texts=\(texts) buttons=\(buttons.map(\.label))")
            guard Self.isInterceptableAlert(texts: texts, buttons: buttons) else {
                Self.debugLog("NC host alert: skipped (not an alarm/timer alert)")
                continue
            }

            let original = axPoint(host, kAXPositionAttribute) ?? .zero
            if Defaults[.notificationHideOriginal] && !notchWouldBeHidden() {
                setWindowPosition(host, CGPoint(x: -2000, y: -2000))
                uncHidden[CFHash(host)] = (host, original)
                Self.debugLog("NC host alert: host hidden off-screen (original=\(original))")
            }

            let title = texts[0]
            let message = texts.dropFirst().joined(separator: " — ")
            let appName = "时钟"
            recordInHistory(
                NotificationRecord(
                    appName: appName, title: title, subtitle: "", body: message, date: Date()))
            if Self.isMuted(appName) {
                Self.debugLog("NC host alert: app muted, history only")
                continue
            }
            Self.debugLog("NC host alert: INTERCEPTED -> notch")
            withAnimation(.smooth(duration: 0.3)) {
                displayedAlert = PendingAlert(
                    appName: appName, title: title, message: message,
                    window: host, trackElement: container, isHostAlert: true,
                    originalPosition: original, buttons: buttons)
            }
        }

        // The alert element vanished (stopped/snoozed/expired): clear the
        // notch display and give the host window its position back.
        if let alert = displayedAlert, alert.isHostAlert {
            let stillThere = containers.contains { CFHash($0) == CFHash(alert.trackElement) }
            if !stillThere {
                displayedAlert = nil
                if let entry = uncHidden.removeValue(forKey: CFHash(alert.window)) {
                    setWindowPosition(entry.window, entry.original)
                }
            }
        }
    }

    private func topAncestorBelow(_ el: AXUIElement, root: AXUIElement) -> AXUIElement? {
        var current = el
        for _ in 0..<10 {
            guard let parent = axParent(current) else { return nil }
            if CFHash(parent) == CFHash(root) { return current }
            current = parent
        }
        return nil
    }

    private func axParent(_ el: AXUIElement) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXParentAttribute as CFString, &v) == .success,
              let parent = v else { return nil }
        return (parent as! AXUIElement)
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

    // MARK: - UserNotificationCenter alerts (alarm/timer/legacy popups)

    /// Alarm, timer and legacy-style alerts are rendered by the
    /// UserNotificationCenter process and never appear as Notification
    /// Center banners — a separate lightweight poll watches its windows.
    private func startUNCWatch() {
        guard uncTimer == nil else { return }
        uncTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scanUNC()
            }
        }
        Self.debugLog("UNC watch: started")
    }

    private func stopUNCWatch() {
        uncTimer?.invalidate()
        uncTimer = nil
        uncSeenWindows.removeAll()
        // Bring back any alert we hid off-screen so nothing is lost if the
        // user disables interception while an alarm is ringing.
        for (_, entry) in uncHidden {
            setWindowPosition(entry.window, entry.original)
        }
        uncHidden.removeAll()
        displayedAlert = nil
    }

    /// Don't hide the system alert while the notch itself would be hidden
    /// (fullscreen) — an invisible ringing alarm with no way to stop it is
    /// worse than the system popup.
    private func notchWouldBeHidden() -> Bool {
        guard Defaults[.hideNotchOption] != .never else { return false }
        return FullscreenMediaDetector.shared.fullscreenStatus.values.contains(true)
    }

    private func findUNCApp() -> AXUIElement? {
        guard let unc = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.UserNotificationCenter"
        }), unc.processIdentifier != 0 else { return nil }
        return AXUIElementCreateApplication(unc.processIdentifier)
    }

    private func scanUNC() {
        guard running, Defaults[.notificationInterceptor] else { return }
        guard let appElement = findUNCApp() else { return }
        let windows = axList(appElement, kAXWindowsAttribute)
        for window in windows {
            handleAlertWindow(window)
        }
        // The alert was dismissed (or the action button closed it): clear
        // the notch display and prune stale bookkeeping.
        if let alert = displayedAlert {
            let stillThere = windows.contains { CFHash($0) == CFHash(alert.window) }
            if !stillThere {
                displayedAlert = nil
                uncHidden.removeValue(forKey: CFHash(alert.window))
            }
        }
        if uncSeenWindows.count > 16 {
            uncSeenWindows = uncSeenWindows.filter { Date().timeIntervalSince($0.value) < 600 }
        }
    }

    private func handleAlertWindow(_ window: AXUIElement) {
        var texts: [String] = []
        collectTexts(window, into: &texts, depth: 0)
        guard !texts.isEmpty else { return }

        let hash = CFHash(window)
        // The alert we are currently showing must never be re-processed (it
        // stays ringing on screen for minutes while hidden).
        if let current = displayedAlert, CFHash(current.window) == hash { return }
        if let seen = uncSeenWindows[hash], Date().timeIntervalSince(seen) < 600 { return }
        uncSeenWindows[hash] = Date()

        // Debug dump so a missed interception can be diagnosed from the log.
        let buttonEls = collectRoleElements(window, role: "AXButton", depth: 0)
        let buttonNames = buttonEls.compactMap { el in
            axStr(el, kAXTitleAttribute) ?? axStr(el, kAXDescriptionAttribute)
        }
        Self.debugLog(
            "UNC alert window: subrole=\(axStr(window, kAXSubroleAttribute) ?? "?") "
                + "title=\(axStr(window, kAXTitleAttribute) ?? "?") texts=\(texts) buttons=\(buttonNames)")

        var buttons: [AlertButton] = []
        for el in buttonEls {
            if let label = axStr(el, kAXTitleAttribute) ?? axStr(el, kAXDescriptionAttribute),
               !label.isEmpty {
                buttons.append(AlertButton(label: label, element: el))
            }
        }

        // Only alarm/timer-style alerts are hijacked. Other
        // UserNotificationCenter windows are consent/security dialogs
        // (calendar access, etc.) that must stay visible and interactive.
        guard Self.isInterceptableAlert(texts: texts, buttons: buttons) else {
            Self.debugLog("UNC alert: skipped (not an alarm/timer alert)")
            return
        }

        let original = axPoint(window, kAXPositionAttribute) ?? .zero
        if Defaults[.notificationHideOriginal] && !notchWouldBeHidden() {
            setWindowPosition(window, CGPoint(x: -2000, y: -2000))
            uncHidden[hash] = (window, original)
            Self.debugLog("UNC alert: hidden off-screen (original=\(original))")
        }

        let title = texts[0]
        let message = texts.dropFirst().joined(separator: " — ")
        let appName = "时钟"
        // History always keeps a copy; muted apps get history only.
        recordInHistory(
            NotificationRecord(
                appName: appName, title: title, subtitle: "", body: message, date: Date()))
        if Self.isMuted(appName) {
            Self.debugLog("UNC alert: app muted, history only")
            return
        }
        withAnimation(.smooth(duration: 0.3)) {
            displayedAlert = PendingAlert(
                appName: appName, title: title, message: message,
                window: window, trackElement: window, isHostAlert: false,
                originalPosition: original, buttons: buttons)
        }
    }

    /// Alarm/timer alerts are recognized by their texts or button labels.
    /// Consent dialogs (TCC prompts: 帮助/不允许/允许…) are excluded even
    /// harder — they must never be hidden or auto-answered.
    private static let alarmAlertKeywords = ["闹钟", "计时器", "alarm", "timer", "snooze", "稍后提醒"]
    private static let consentDialogKeywords = ["不允许", "don't allow", "帮助", "help"]

    static func isInterceptableAlert(texts: [String], buttons: [AlertButton]) -> Bool {
        let labels = buttons.map { $0.label.lowercased() }
        if labels.contains(where: { label in
            consentDialogKeywords.contains { label.contains($0) }
        }) {
            return false
        }
        let haystack = (texts + buttons.map(\.label)).joined(separator: " ").lowercased()
        return alarmAlertKeywords.contains { haystack.contains($0) }
    }

    /// Press one of the intercepted alert's real buttons from the notch.
    func pressAlertButton(_ label: String) {
        guard let alert = displayedAlert,
              let button = alert.buttons.first(where: { $0.label == label }) else { return }
        let err = AXUIElementPerformAction(button.element, kAXPressAction as CFString)
        Self.debugLog("UNC alert: press \(label) err=\(err.rawValue)")
        if err != .success {
            // The press failed — bring the system alert back so nothing is lost.
            setWindowPosition(alert.window, alert.originalPosition)
            uncHidden.removeValue(forKey: CFHash(alert.window))
        }
        withAnimation(.smooth(duration: 0.3)) {
            displayedAlert = nil
        }
    }

    private func setWindowPosition(_ window: AXUIElement?, _ position: CGPoint) {
        guard let window else { return }
        var target = position
        guard let value = AXValueCreate(.cgPoint, &target) else { return }
        let err = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
        if err != .success {
            Self.debugLog("UNC alert: set position err=\(err.rawValue)")
        }
    }

    private func collectRoleElements(_ el: AXUIElement, role: String, depth: Int) -> [AXUIElement] {
        guard depth < 12 else { return [] }
        var out: [AXUIElement] = []
        if (axStr(el, kAXRoleAttribute) ?? "") == role {
            out.append(el)
        }
        for child in axList(el, kAXChildrenAttribute) {
            out.append(contentsOf: collectRoleElements(child, role: role, depth: depth + 1))
        }
        return out
    }

    private func axPoint(_ el: AXUIElement, _ name: String) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success,
              let point = v, AXValueGetType(point as! AXValue) == .cgPoint else { return nil }
        var cg = CGPoint.zero
        AXValueGetValue(point as! AXValue, .cgPoint, &cg)
        return cg
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
        // zh banners separate with "，" (e.g. iPhone-forwarded notifications
        // arrive as "抖音，标题…"), so trailing separators must go too or the
        // app-icon lookup never matches.
        var appName = ""
        if !title.isEmpty, let range = desc.range(of: title) {
            appName = String(desc[..<range.lowerBound]).trimmingCharacters(
                in: CharacterSet(charactersIn: "，、；：,;: \t"))
        }
        if appName.isEmpty { appName = "通知" }

        Self.debugLog("extract: texts=\(texts) appName=\(appName)")
        return NotificationRecord(appName: appName, title: title, subtitle: subtitle, body: body, date: Date())
    }

    // MARK: - Display

    /// Muted apps never pop the sneak peek; their notifications are only
    /// recorded in the history list.
    static func isMuted(_ appName: String) -> Bool {
        Defaults[.notificationMutedApps].contains(appName)
    }

    private func recordInHistory(_ record: NotificationRecord) {
        recentNotifications.insert(record, at: 0)
        let limit = max(5, Defaults[.notificationHistoryLimit])
        if recentNotifications.count > limit {
            recentNotifications.removeLast(recentNotifications.count - limit)
        }
    }

    private func display(_ record: NotificationRecord) {
        recordInHistory(record)
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
