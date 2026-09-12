//
//  PomodoroManager.swift
//  boringNotch
//
//  Created by imac on 2026. 09. 12..
//

import AppKit
import Combine
import Defaults
import Foundation

extension Notification.Name {
    /// Posted on the main thread when a pomodoro phase finishes and the notch
    /// should pop open with the reminder. The AppDelegate decides whether the
    /// notch can actually be shown (it may be hidden in fullscreen).
    static let pomodoroPhaseEnded = Notification.Name("pomodoroPhaseEnded")
}

@MainActor
final class PomodoroManager: ObservableObject {
    static let shared = PomodoroManager()

    enum Phase: Equatable {
        case focus
        case shortBreak
        case longBreak

        var isBreak: Bool { self != .focus }
    }

    static let sessionsPerLongBreak = 4
    /// How long a reminder keeps retrying while the notch is hidden in fullscreen.
    private static let reminderRetryWindow: TimeInterval = 120

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var completedFocusSessions = 0
    /// Playful headline shown in the pomodoro tab after an automatic phase
    /// change; nil falls back to the phase's default headline.
    @Published private(set) var reminderMessage: String?

    private var endAt: Date?
    private var remainingOnPause: TimeInterval?
    private var endTimer: Timer?
    private var pendingReminderUntil: Date?
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        // Re-show a reminder that was deferred because the notch was hidden
        // (fullscreen media) as soon as the notch becomes visible again.
        FullscreenMediaDetector.shared.$fullscreenStatus
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.retryDeferredReminder()
            }
            .store(in: &cancellables)
    }

    // MARK: - Display state

    var phaseDuration: TimeInterval {
        switch phase {
        case .focus: return Defaults[.pomodoroFocusDuration]
        case .shortBreak: return Defaults[.pomodoroShortBreakDuration]
        case .longBreak: return Defaults[.pomodoroLongBreakDuration]
        }
    }

    /// Seconds left in the current phase. Pure wall-clock math, so the
    /// countdown stays correct across sleep/wake without re-arming timers.
    /// Not published — views poll it via TimelineView at 1 Hz.
    var remaining: TimeInterval {
        if let endAt {
            return max(0, endAt.timeIntervalSinceNow)
        }
        return remainingOnPause ?? phaseDuration
    }

    /// True while a session is either running or paused mid-phase. A freshly
    /// reset timer is not active, so the closed notch keeps showing music/face.
    var isActive: Bool {
        isRunning || remainingOnPause != nil
    }

    /// Focus sessions completed within the current cycle (0..<sessionsPerLongBreak).
    var cycleProgress: Int {
        completedFocusSessions % Self.sessionsPerLongBreak
    }

    static func formatted(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let seconds = total % 60
        let minutes = (total / 60) % 60
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Controls

    func startOrResume() {
        guard !isRunning else { return }
        let duration = remainingOnPause ?? phaseDuration
        remainingOnPause = nil
        beginCountdown(duration: duration)
    }

    func toggle() {
        if isRunning {
            pause()
        } else {
            startOrResume()
        }
    }

    func pause() {
        guard isRunning else { return }
        stopEndTimer()
        remainingOnPause = remaining
        endAt = nil
        isRunning = false
    }

    /// Advance to the next phase immediately and start it running.
    /// Skipping a focus phase does not count towards the long-break cycle.
    func skip() {
        stopEndTimer()
        endAt = nil
        remainingOnPause = nil
        reminderMessage = nil
        advance(from: phase)
    }

    /// Stop everything and return to a fresh focus session.
    func reset() {
        stopEndTimer()
        endAt = nil
        remainingOnPause = nil
        pendingReminderUntil = nil
        reminderMessage = nil
        phase = .focus
        isRunning = false
        completedFocusSessions = 0
    }

    // MARK: - Phase engine

    private func beginCountdown(duration: TimeInterval) {
        let end = Date().addingTimeInterval(max(1, duration))
        endAt = end
        isRunning = true

        let timer = Timer(fire: end, interval: 0, repeats: false, block: { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endTimerFired()
            }
        })
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        endTimer = timer
    }

    private func stopEndTimer() {
        endTimer?.invalidate()
        endTimer = nil
    }

    private func endTimerFired() {
        endTimer = nil
        guard let endAt, Date() >= endAt else {
            // Fired early (should not happen) — re-arm for the real end.
            if let endAt {
                beginCountdown(duration: endAt.timeIntervalSinceNow)
            }
            return
        }
        self.endAt = nil
        remainingOnPause = nil

        let finished = phase
        if finished == .focus {
            completedFocusSessions += 1
        }
        advance(from: finished)
        announce()
    }

    /// Switch to the next phase and immediately start its countdown.
    private func advance(from finished: Phase) {
        switch finished {
        case .focus:
            let completed = completedFocusSessions
            phase = (completed > 0 && completed % Self.sessionsPerLongBreak == 0)
                ? .longBreak
                : .shortBreak
        case .shortBreak, .longBreak:
            phase = .focus
        }
        beginCountdown(duration: phaseDuration)
    }

    // MARK: - Reminder

    private static let focusEndMessages = [
        "番茄熟啦，去休息一下吧 🍅",
        "去喝口水，眨眨眼睛 💧",
        "站起来伸个懒腰吧～",
        "眼睛想放个假，去窗边看看远处 👀",
        "摸鱼五分钟，快乐一整天 🐟",
        "给大脑充个电，回来再战 🔋",
        "偷偷躺平一会儿，没人看见 😌",
    ]

    private static let longBreakStartMessages = [
        "四连胜！奖励自己一个长休息 🎉",
        "好好歇会儿，出门散个步吧 🌿",
        "这么专注，值得一个长长的大休息 ☕️",
    ]

    private static let breakEndMessages = [
        "满血复活，继续冲 ⚡️",
        "休息够啦，回来开工 💪",
        "新的一轮，稳住，我们能赢 🔥",
        "番茄计时器想你了，快回来 🍅",
        "精神满满，冲鸭 ✨",
    ]

    /// Called after the phase has advanced; picks a fresh playful message for
    /// the phase the timer just entered.
    private func announce() {
        pendingReminderUntil = nil
        switch phase {
        case .focus:
            reminderMessage = Self.breakEndMessages.randomElement()
        case .shortBreak:
            reminderMessage = Self.focusEndMessages.randomElement()
        case .longBreak:
            reminderMessage = Self.longBreakStartMessages.randomElement()
        }
        SystemSound.play(Defaults[.pomodoroSoundName])
        NotificationCenter.default.post(name: .pomodoroPhaseEnded, object: nil)
    }

    /// Called by the AppDelegate when the phase ended while the notch could
    /// not be shown (hidden in fullscreen). The reminder is retried whenever
    /// the fullscreen state changes within the retry window.
    func markReminderDeferred() {
        pendingReminderUntil = Date().addingTimeInterval(Self.reminderRetryWindow)
    }

    private func retryDeferredReminder() {
        guard let until = pendingReminderUntil else { return }
        guard Date() < until else {
            pendingReminderUntil = nil
            return
        }
        NotificationCenter.default.post(name: .pomodoroPhaseEnded, object: nil)
    }
}
