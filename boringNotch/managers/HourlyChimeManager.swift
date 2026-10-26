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

    /// A playful time announcement for the current hour. The pieces are
    /// catalog keys resolved with the selected app language; the message is
    /// composed when the chime fires (a 3-second banner, no live update).
    static func randomMessage(for date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        let timeKey: String
        let displayHour: Int
        let tails: [String]
        switch hour {
        case 0..<5:
            timeKey = "Late night %lld o'clock"
            displayHour = hour
            tails = ["It's late — get some rest 🌙", "Still up? Tomorrow-you will thank you 😴", "The world is asleep, but not you 🌌"]
        case 5..<11:
            timeKey = "Morning %lld o'clock"
            displayHour = hour
            tails = ["A fresh hour, full of energy ✨", "A beautiful day begins ☀️", "Time to stretch 🙆"]
        case 11..<13:
            timeKey = "Noon %lld o'clock"
            displayHour = hour
            tails = ["Lunch time 🍚", "Nap time 😌", "Eat well, work well 🍜"]
        case 13..<18:
            timeKey = "Afternoon %lld o'clock"
            displayHour = hour - 12
            tails = ["Move around, don't sit too long 🌤", "Coffee refill time ☕️", "Give your eyes some distance 👀"]
        case 18..<23:
            timeKey = "Evening %lld o'clock"
            displayHour = hour - 12
            tails = ["Time to wind down 🌙", "Sneak a little break, no one's watching 🐟", "Good evening, keep it up 💪"]
        default:
            timeKey = "Evening 11 o'clock"
            displayHour = 11
            tails = ["Wrap up for today 🌙", "One more moment, then sleep 😴"]
        }
        let timeText = L10n.string(timeKey, displayHour)
        let tail = L10n.string(tails.randomElement() ?? "Hourly chime ⏰")
        return L10n.string("%@ %@", timeText, tail)
    }
}
