<h1 align="center">boring.notch-plus</h1>

<p align="center">
  <a href="README.md">中文</a> · <strong>English</strong>
</p>

<p align="center">
  Turn your MacBook's notch into a productivity hub — an enhanced fork of the wonderful
  <a href="https://github.com/TheBoredTeam/boring.notch">TheBoredTeam/boring.notch</a>.
</p>

> [!IMPORTANT]
> This project is a **fork** of [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch). The original project is licensed under **GPL-3.0**, and this repository is open-sourced under the same license. All core credit goes to the original authors and contributors — this fork simply builds on top of their work.

## ✨ What's new compared to the original

| Feature | Description |
|---|---|
| 🍅 **Pomodoro timer** | Standard 25/5 cycles (long break every 4 rounds) with the countdown living inside your notch; automatic break pop-ups with playful messages and selectable system sounds |
| ⏰ **Hourly chime** | A playful time announcement below the notch at the top of every hour; automatically silenced while the screen is locked or asleep |
| 🌤️ **Idle weather** | When nothing else is showing, the notch displays a weather icon with the current temperature (free Open-Meteo data, IP-based location with manual city override) |
| 🗑️ **One-click shelf clear** | A trash button in the Shelf panel removes every item at once — real files are never touched |
| 🎵 **Music + countdown coexistence** | While a Pomodoro session runs, the closed notch shows both the album art and the countdown |
| 🔊 **Sound picker** | Choose from 14 macOS system sounds (with preview) for the Pomodoro reminder and the hourly chime, or mute them |
| 🐛 **Drag-and-drop fix** | Fixes "dragging a file onto the notch does nothing" under the app sandbox (macOS 26) |
| 🚫 **Independent version line** | Detached from the official Sparkle update feed — official releases can never overwrite this fork |

All original features (music controls, calendar, shelf, HUD replacement, camera mirror, …) are fully preserved — see the [original README](https://github.com/TheBoredTeam/boring.notch#readme).

## 📥 Install

1. Grab the latest `boringNotch-1.0.0.dmg` from [Releases](https://github.com/y2050802852-ux/boring.notch-plus/releases)
2. Open the DMG and drag **boringNotch.app** into Applications
3. If macOS warns about an unidentified developer: System Settings → Privacy & Security → **Open Anyway** (this project is ad-hoc signed)

**Requirements**: macOS 14 Sonoma or later · Apple Silicon

> [!NOTE]
> Some features need permission grants: Calendar/Reminders (EventKit), Camera (mirror), Accessibility (HUD replacement), Apple Events (music/Spotify control). Denying any of them only disables that specific feature.

## 🛠️ Building from source

- **Xcode 16.0 or later**
- macOS 14+

```bash
git clone https://github.com/y2050802852-ux/boring.notch-plus.git
cd boring.notch-plus
open boringNotch.xcodeproj   # hit Cmd+R in Xcode
```

Command-line build + DMG:

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination "generic/platform=macOS" \
  ENABLE_HARDENED_RUNTIME=NO build
hdiutil create -volname "boringNotch" \
  -srcfolder ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Release/boringNotch.app \
  -ov -format UDZO boringNotch.dmg
```

> [!NOTE]
> `ENABLE_HARDENED_RUNTIME=NO` matters for local ad-hoc builds: with hardened runtime enabled, dyld library validation rejects the ad-hoc re-signed embedded MediaRemoteAdapter.framework and the app crashes at launch. Remove the flag when signing with a real certificate.

## 📄 License

This project is open-sourced under the [GPL-3.0](LICENSE) license, same as the original project.

- Original project copyright © [TheBoredTeam](https://github.com/TheBoredTeam)
- Modifications in this fork are equally published under GPL-3.0

## 🙏 Acknowledgments

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) — the foundation of this project
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — Now Playing support on macOS 15.4+
- [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) — inspiration for the Shelf feature
- [Open-Meteo](https://open-meteo.com/) — free, key-less weather data
- Every open-source dependency listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)
