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
        if let message = pomodoro.reminderMessage {
            return message
        }
        switch pomodoro.phase {
        case .focus:
            return pomodoro.isRunning ? "专注中 🍅" : "准备专注 🍅"
        case .shortBreak:
            return "休息一下 ☕️"
        case .longBreak:
            return "长休息 🌿"
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
//
// With music playing the album art is kept on the left and the countdown takes
// the right slot; without music the countdown sits alone next to the notch.

struct PomodoroLiveActivity: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var musicManager = MusicManager.shared
    let albumArtNamespace: Namespace.ID

    static let slotWidth: CGFloat = 80

    private var musicActive: Bool {
        musicManager.isPlaying || !musicManager.isPlayerIdle
    }

    private var sideSize: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12)
    }

    private var fontSize: CGFloat {
        min(12, max(9, vm.effectiveClosedNotchHeight * 0.4))
    }

    var body: some View {
        HStack(spacing: 0) {
            if musicActive {
                Image(nsImage: musicManager.albumArt)
                    .resizable()
                    .clipped()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                    )
                    .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                    .frame(width: sideSize, height: sideSize)
            } else {
                Rectangle()
                    .fill(.clear)
                    .frame(width: sideSize)
            }

            Rectangle()
                .fill(.black)
                .frame(width: max(0, vm.closedNotchSize.width - 20))

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 4) {
                    Text("🍅")
                        .font(.system(size: fontSize))
                    Text(PomodoroManager.formatted(PomodoroManager.shared.remaining))
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .fixedSize()
                .padding(.trailing, 4)
                .frame(width: Self.slotWidth, alignment: .trailing)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
