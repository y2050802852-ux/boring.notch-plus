//
//  HourlyChimeManager.swift
//  boringNotch
//
//  Created by imac on 2026. 09. 12..
//

import AppKit
import Combine
import Defaults
import Foundation

extension Notification.Name {
    /// Posted on the main thread at the top of each hour (when enabled). The
    /// sound is played by the manager; the AppDelegate decides whether the
    /// visual banner below the notch can be shown.
    static let hourlyChimeTriggered = Notification.Name("hourlyChimeTriggered")
}

@MainActor
final class HourlyChimeManager: ObservableObject {
    static let shared = HourlyChimeManager()

    /// Only chime when the timer actually fires within this window of the
    /// hour boundary: after waking from sleep an overdue timer fires
    /// immediately and is silently skipped instead of chiming for an hour
    /// that passed hours ago.
    private static let gracePeriod: TimeInterval = 60

    private var chimeTimer: Timer?
    private var isScreenLocked = false
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Stay silent while the screen is locked (no makeup chime on unlock;
        // the schedule simply resumes at the next hour).
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = true
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(rawValue: "com.apple.screenIsUnlocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isScreenLocked = false
            }
        }

        Defaults.publisher(.hourlyChimeEnabled)
            .receive(on: RunLoop.main)
            .sink { [weak self] change in
                change.newValue ? self?.scheduleNext() : self?.stop()
            }
            .store(in: &cancellables)

        // Re-arm after sleep/wake; the overdue fire is skipped by the
        // grace-period guard and the next hour is scheduled fresh.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, Defaults[.hourlyChimeEnabled] else { return }
                self.scheduleNext()
            }
        }

        if Defaults[.hourlyChimeEnabled] {
            scheduleNext()
        }
    }

    private func scheduleNext() {
        chimeTimer?.invalidate()
        let next = Calendar.current.nextDate(
            after: Date(),
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(3600)
        let timer = Timer(fire: next, interval: 0, repeats: false, block: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fired(at: next)
            }
        })
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        chimeTimer = timer
    }

    private func stop() {
        chimeTimer?.invalidate()
        chimeTimer = nil
    }

    private func fired(at scheduled: Date) {
        scheduleNext()
        guard Date().timeIntervalSince(scheduled) < Self.gracePeriod else { return }

        // Locked screen: skip this hour entirely (sleep is already covered —
        // an overdue fire after wake fails the grace-period check above).
        guard !isScreenLocked else { return }
        chime()
    }

    private func chime() {
        SystemSound.play(Defaults[.hourlyChimeSoundName])
        NotificationCenter.default.post(
            name: .hourlyChimeTriggered,
            object: nil,
            userInfo: ["message": Self.randomMessage()]
        )
    }

    /// A playful time announcement for the current hour, e.g. "下午 3 点，来杯咖啡续命 ☕️".
    static func randomMessage(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let timeText: String
        let tails: [String]
        switch hour {
        case 0..<5:
            timeText = "凌晨 \(hour) 点"
            tails = ["夜深了，早点休息 🌙", "还不睡吗，明天会感谢你的 😴", "世界都睡了，就你还醒着 🌌"]
        case 5..<11:
            timeText = "早上 \(hour) 点"
            tails = ["新的一小时，精神满满 ✨", "美好的一天开始啦 ☀️", "起来伸个懒腰吧 🙆"]
        case 11..<13:
            timeText = "中午 \(hour) 点"
            tails = ["干饭时间到 🍚", "午休走起 😌", "吃饱了才有力气干活 🍜"]
        case 13..<18:
            timeText = "下午 \(hour - 12) 点"
            tails = ["起来晃晃，别久坐 🌤", "来杯咖啡续命 ☕️", "眼睛想看看远处 👀"]
        case 18..<23:
            timeText = "晚上 \(hour - 12) 点"
            tails = ["该收摊啦 🌙", "摸鱼一会儿，没人看见 🐟", "晚上好，继续加油 💪"]
        default:
            timeText = "晚上 11 点"
            tails = ["今天也要收工了 🌙", "再玩一会儿就睡哦 😴"]
        }
        return "\(timeText)，\(tails.randomElement() ?? "整点报时 ⏰")"
    }
}
