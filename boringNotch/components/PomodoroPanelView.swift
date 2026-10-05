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

    // Closed-notch geometry mirrors MusicLiveActivity: a sideSize block
    // centered in a left slot matching the music/idle states, then a wider
    // countdown slot on the right so the pomodoro notch leans appropriately
    // wider without going lopsided.
    static let slotWidth: CGFloat = 56

    private var sideSlot: CGFloat {
        max(0, vm.effectiveClosedNotchHeight - 12) + 10
    }

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
            Group {
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
            }
            .frame(width: sideSlot)

            Rectangle()
                .fill(.black)
                .frame(width: max(0, vm.closedNotchSize.width))

            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(PomodoroManager.formatted(PomodoroManager.shared.remaining))
                    .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: Self.slotWidth, alignment: .center)
                    // The pomodoro bar is asymmetric (left slot + notch width
                    // + 56pt slot); when the whole bar is screen-centered the
                    // countdown lands ~5pt left of the visible black region's
                    // center. Nudge it back so it looks centered.
                    .offset(x: 5)
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }
}
