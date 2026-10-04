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

/// The row that appears BELOW the notch bar while a notification is being
/// transcribed — the notch expands downward to reveal it.
struct NotificationSneakPeekView: View {
    let record: NotificationRecord

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.fill")
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.12)))

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
}

/// The「通知」tab in the open notch: the recent-notification history.
struct NotificationListView: View {
    @ObservedObject private var interceptor = NotificationInterceptor.shared

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
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.gray)
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
    }
}
