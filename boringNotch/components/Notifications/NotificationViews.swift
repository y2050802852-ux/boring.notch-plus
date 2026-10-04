//
//  NotificationViews.swift
//  boringNotch
//
//  1.1.0 notification replacement UI: the closed-notch sneak peek and the
//  recent-notifications list shown in the open notch.
//

import SwiftUI
import Defaults

struct NotificationSneakPeekView: View {
    @EnvironmentObject var vm: BoringViewModel
    let record: NotificationRecord

    private var sideSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var sideSlot: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12) + 10
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left slot: bell icon centered in the black extension
            Image(systemName: "bell.fill")
                .font(.system(size: min(14, max(10, sideSize * 0.5))))
                .foregroundStyle(.white)
                .frame(width: sideSize, height: sideSize)
                .frame(width: sideSlot)

            // Filler: app name / title / body (covers the hardware notch)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.appName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
                Text(record.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(record.subtitle.isEmpty ? record.body : "\(record.subtitle) — \(record.body)")
                    .font(.system(size: 9))
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            .frame(width: max(0, vm.closedNotchSize.width), alignment: .leading)
            .padding(.horizontal, 2)

            // Right slot: empty for symmetry
            Color.clear
                .frame(width: sideSlot)
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}

struct NotificationListView: View {
    @ObservedObject private var interceptor = NotificationInterceptor.shared
    @ObservedObject private var coordinator = BoringViewCoordinator.shared

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
