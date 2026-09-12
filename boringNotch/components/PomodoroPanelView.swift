//
//  PomodoroPanelView.swift
//  boringNotch
//
//  Created by imac on 2026. 09. 12..
//

import Defaults
import SwiftUI

// MARK: - Open-state tab panel

struct PomodoroPanelView: View {
    @ObservedObject var pomodoro = PomodoroManager.shared

    private var headline: String {
        switch pomodoro.phase {
        case .focus:
            return pomodoro.isRunning ? "Focus in progress 🍅" : "Ready to focus 🍅"
        case .shortBreak:
            return "Take a break ☕️"
        case .longBreak:
            return "Long break 🌿"
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                if pomodoro.phase == .focus {
                    cycleDots
                }
            }
            .animation(.smooth, value: pomodoro.phase)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(PomodoroManager.formatted(pomodoro.remaining))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 18) {
                HoverButton(icon: "arrow.counterclockwise", iconColor: .gray) {
                    pomodoro.reset()
                }
                .help("Reset")

                HoverButton(
                    icon: pomodoro.isRunning ? "pause.fill" : "play.fill",
                    iconColor: .white,
                    scale: .large
                ) {
                    pomodoro.toggle()
                }
                .help(pomodoro.isRunning ? "Pause" : "Start")

                HoverButton(icon: "forward.end.fill", iconColor: .gray) {
                    pomodoro.skip()
                }
                .help(pomodoro.phase.isBreak ? "Skip break" : "Skip to break")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.smooth, value: pomodoro.isRunning)
    }

    private var cycleDots: some View {
        HStack(spacing: 4) {
            ForEach(0..<PomodoroManager.sessionsPerLongBreak, id: \.self) { index in
                Circle()
                    .fill(index < pomodoro.cycleProgress ? Color.white : Color.white.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

// MARK: - Closed-state live activity (right of the real notch)

struct PomodoroLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel

    private var fontSize: CGFloat {
        min(13, max(9, vm.effectiveClosedNotchHeight * 0.42))
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.clear)
                .frame(width: max(0, vm.effectiveClosedNotchHeight - 12))

            Rectangle()
                .fill(.black)
                .frame(width: vm.closedNotchSize.width - 20)

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 4) {
                    Text("🍅")
                        .font(.system(size: fontSize))
                    Text(PomodoroManager.formatted(PomodoroManager.shared.remaining))
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(width: 64)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
