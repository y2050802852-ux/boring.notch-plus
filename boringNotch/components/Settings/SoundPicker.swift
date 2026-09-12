//
//  SoundPicker.swift
//  boringNotch
//
//  Created by imac on 2026. 09. 12..
//

import AppKit
import SwiftUI

/// The 14 macOS system alert sounds. The sentinel "none" means silent.
enum SystemSound {
    static let none = "none"
    static let names = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
        "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
    ]

    /// Plays a system sound by name; "none" is silent.
    static func play(_ name: String) {
        guard name != Self.none, let sound = NSSound(named: name) else { return }
        sound.play()
    }
}

/// Selectable list of the system sounds with a per-row preview button.
/// The bound value is the sound name, or `SystemSound.none` for silent.
struct SoundPicker: View {
    @Binding var selection: String
    @State private var previewing: NSSound?

    var body: some View {
        List {
            row(SystemSound.none, label: "None", previewable: false)
            ForEach(SystemSound.names, id: \.self) { name in
                row(name, label: name, previewable: true)
            }
        }
        .listStyle(.inset)
        .frame(height: 230)
    }

    private func row(_ name: String, label: String, previewable: Bool) -> some View {
        HStack {
            HStack(spacing: 6) {
                Image(
                    systemName: selection == name
                        ? "largecircle.fill.circle" : "circle"
                )
                .foregroundStyle(Color.accentColor)
                Text(label)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                selection = name
            }

            if previewable {
                Button {
                    playPreview(name)
                } label: {
                    Image(systemName: "speaker.wave.1.fill")
                }
                .buttonStyle(.plain)
                .help("Preview")
            }
        }
        .padding(.vertical, 2)
    }

    private func playPreview(_ name: String) {
        previewing?.stop()
        guard let sound = NSSound(named: name) else { return }
        previewing = sound
        sound.play()
    }
}
