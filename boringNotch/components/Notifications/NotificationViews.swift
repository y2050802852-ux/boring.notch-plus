//
//  NotificationViews.swift
//  boringNotch
//
//  1.1.0 notification replacement UI: the notch EXPANDS DOWNWARD (like the
//  volume sneak-peek, but taller) to reveal the notification content — the
//  hardware notch itself stays untouched, so nothing is hidden behind the
//  camera housing.
//

import SwiftUI
import Defaults

/// Resolves the real app icon for an intercepted notification. Notification
/// Center banners only expose the app's display name over the Accessibility
/// API, so the icon is matched by name: running apps first, then a cached
/// scan of installed app bundles. Unknown apps fall back to the bell
/// placeholder in the views.
@MainActor
enum NotificationAppIcon {
    private static var cache: [String: NSImage] = [:]
    private static var installedAppsByName: [String: String]?

    static func icon(for appName: String) -> NSImage? {
        let name = appName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name != "通知" else { return nil }
        if let cached = cache[name] { return cached }

        let icon = runningAppIcon(for: name) ?? installedAppIcon(for: name)
        if let icon { cache[name] = icon }
        return icon
    }

    private static func runningAppIcon(for name: String) -> NSImage? {
        NSWorkspace.shared.runningApplications.first {
            $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
        }?.icon
    }

    private static func installedAppIcon(for name: String) -> NSImage? {
        if installedAppsByName == nil { installedAppsByName = scanInstalledApps() }
        guard let path = installedAppsByName?[name.lowercased()] else { return nil }
        return NSWorkspace.shared.icon(forFile: path)
    }

    private static func scanInstalledApps() -> [String: String] {
        var map: [String: String] = [:]
        let roots = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Library/CoreServices",
            NSString("~/Applications").expandingTildeInPath,
        ]
        for root in roots {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            for item in items where item.hasSuffix(".app") {
                register(path: root + "/" + item, into: &map)
            }
        }
        return map
    }

    private static func register(path: String, into map: inout [String: String]) {
        // displayName keeps the .app suffix; strip it so keys are plain names.
        let display = FileManager.default.displayName(atPath: path)
        let trimmed = display.hasSuffix(".app") ? String(display.dropLast(4)) : display
        map[trimmed.lowercased()] = path
        guard let bundle = Bundle(url: URL(fileURLWithPath: path)) else { return }
        for key in [kCFBundleNameKey as String, "CFBundleDisplayName"] {
            let name = bundle.localizedInfoDictionary?[key] as? String
                ?? bundle.infoDictionary?[key] as? String
            if let name { map[name.lowercased()] = path }
        }
    }
}

/// The row that appears BELOW the notch bar while a notification is being
/// transcribed — the notch expands downward to reveal it.
struct NotificationSneakPeekView: View {
    let record: NotificationRecord

    /// Long notifications widen the bar up to this width, then wrap the body
    /// to a second line instead of stretching across the whole notch window.
    static let maxWidth: CGFloat = 480

    /// Single-line width of the widest text the row renders (title at 12pt
    /// semibold vs body at 10pt regular), measured with the same system fonts
    /// the row uses so CJK and Latin text both size correctly.
    static func textWidth(for record: NotificationRecord) -> CGFloat {
        func measured(_ text: String, size: CGFloat, weight: NSFont.Weight) -> CGFloat {
            (text as NSString).size(
                withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]
            ).width
        }
        let bodyText = record.subtitle.isEmpty ? record.body : "\(record.subtitle) — \(record.body)"
        return max(
            measured(record.title, size: 12, weight: .semibold),
            measured(bodyText, size: 10, weight: .regular)
        )
    }

    /// Row width for a record: hugs short notifications at `floor` (the base
    /// bar width) and grows with the text up to `maxWidth`.
    static func contentWidth(for record: NotificationRecord, floor: CGFloat) -> CGFloat {
        // icon 26 + spacing 10 + time ≈ 42 + horizontal padding 28 + slack 6
        let natural = textWidth(for: record) + 112
        return min(max(natural, floor), max(floor, maxWidth))
    }

    var body: some View {
        HStack(spacing: 10) {
            appIcon
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.appName)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                Text(record.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if !record.body.isEmpty {
                    Text(record.subtitle.isEmpty ? record.body : "\(record.subtitle) — \(record.body)")
                        .font(.system(size: 10))
                        .foregroundStyle(.gray)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            Text(record.date, style: .time)
                .font(.system(size: 9))
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// The sending app's real icon; the bell placeholder when the app name
    /// can't be matched to an installed/running app.
    @ViewBuilder
    private var appIcon: some View {
        if let icon = NotificationAppIcon.icon(for: record.appName) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
    }
}

/// The「通知」tab in the open notch: the recent-notification history.
struct NotificationListView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var interceptor = NotificationInterceptor.shared
    @Default(.notificationMutedApps) private var mutedApps: [String]

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Notifications")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !interceptor.recentNotifications.isEmpty {
                    HoverButton(icon: "trash", iconColor: .gray) {
                        interceptor.clearHistory()
                    }
                    .help("Clear notifications")
                }
            }

            if interceptor.recentNotifications.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "bell.slash")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white, .gray)
                        .imageScale(.large)
                    if !Defaults[.notificationInterceptor] {
                        Text("Notification interception is off")
                            .foregroundStyle(.gray)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                        Text("Enable it in Settings → Notifications")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    } else if !interceptor.accessibilityGranted {
                        Text("Accessibility permission required")
                            .foregroundStyle(.gray)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Text("No notifications yet")
                            .foregroundStyle(.gray)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                    }
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(interceptor.recentNotifications) { record in
                            HStack(alignment: .top, spacing: 10) {
                                rowAppIcon(for: record)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(record.appName)
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(.gray)
                                        Spacer()
                                        Text(record.date, style: .time)
                                            .font(.system(size: 9))
                                            .foregroundStyle(.gray)
                                    }
                                    Text(record.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                    Text(record.subtitle.isEmpty ? record.body : "\(record.subtitle) — \(record.body)")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.gray)
                                        .lineLimit(2)
                                }
                                muteButton(for: record)
                            }
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
    }

    /// The sending app's real icon for a history row; bell placeholder when
    /// unmatched.
    @ViewBuilder
    private func rowAppIcon(for record: NotificationRecord) -> some View {
        if let icon = NotificationAppIcon.icon(for: record.appName) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 20, height: 20)
        } else {
            Image(systemName: "bell.fill")
                .font(.system(size: 12))
                .foregroundStyle(.gray)
        }
    }

    /// One-click mute: hides future sneak peeks from this app while keeping
    /// them in the history. Tapping again unmutes.
    private func muteButton(for record: NotificationRecord) -> some View {
        let isMuted = mutedApps.contains(record.appName)
        return Button {
            if isMuted {
                mutedApps.removeAll { $0 == record.appName }
            } else {
                mutedApps.append(record.appName)
            }
        } label: {
            Image(systemName: isMuted ? "bell.slash.fill" : "bell.slash")
                .font(.system(size: 11))
                .foregroundStyle(isMuted ? Color.white : Color(white: 0.45))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isMuted ? "Unmute this app" : "Mute this app")
    }
}
