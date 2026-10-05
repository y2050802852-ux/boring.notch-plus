<h1 align="center">boring.notch-plus</h1>

<p align="center">
  <a href="README.md">中文</a> · <strong>English</strong>
</p>

<p align="center">
  Turn your MacBook's notch into a productivity hub — an enhanced fork of the wonderful
  <a href="https://github.com/TheBoredTeam/boring.notch">TheBoredTeam/boring.notch</a>.
</p>

> [!IMPORTANT]
> This project is a **fork** of [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch). The original project is licensed under **GPL-3.0**, and this repository is open-sourced under the same license. All core credit goes to the original authors and contributors — this fork simply builds on top of their work with a large set of new features.

## ✨ What's new compared to the original

### 📢 Notification replacement (the headline feature)

| Feature | Description |
|---|---|
| 📥 **Banner interception** | Notifications from third-party apps are transcribed into the notch — it expands downward to show the app icon, title and body, while the system banner in the top-right corner never bothers you again. Notifications are still kept in Notification Center's list |
| 🚫 **System notifications fully blocked** | Banners from system apps (Software Update, Clock, System Settings, Screen Time) are hidden outright — the notch **only shows third-party, non-system notifications**; system consent dialogs (calendar, accessibility, …) are completely untouched |
| 🕘 **Notification history** | Click the 🔔 tab in the notch to review recent notifications at any time, with one-click clear |
| 🖼️ **Real app icons** | Both the pop-up and the history list show the sender's real icon (a WeChat notification shows the WeChat icon) |
| 👆 **Click to open** | Click any pop-up or history entry to activate/launch the app that sent it |
| 📏 **Dynamic width** | Short notifications stay nearly as wide as the notch; long ones widen up to a cap and then wrap — never stretched across the whole screen |
| 🔇 **Mute list** | Add noisy apps to a mute list — no pop-ups, but entries are still kept in the history; mute directly from a history row with one click |

> [!NOTE]
> Notification replacement must be enabled in Settings → Notifications and requires Accessibility permission. The native alarm's full-screen alert does not go through Notification Center and cannot be intercepted (system limitation).

### 📋 Clipboard history

| Feature | Description |
|---|---|
| 📋 **Automatic capture** | Everything you copy — **text and images** — lands in the history; click the **clipboard icon in the notch's top-right corner** to browse it |
| 👆 **Click to re-copy** | Click any entry to put it back on the clipboard (a ✓ appears on the row), then ⌘V anywhere |
| 💾 **Disk persistence** | History survives app/system restarts; 50 entries by default (10–200 adjustable), oldest ones are evicted automatically |
| 🔒 **Privacy red line** | Copies flagged as concealed (1Password, Bitwarden, …) are **never recorded**; clear the entire history at any time |
| ⌨️ **Global shortcut** | **⌘⇧C** opens the clipboard panel by default, press again to close; customizable in Settings → Shortcuts |

### 🍅 Productivity enhancements (earlier releases)

| Feature | Description |
|---|---|
| 🍅 **Pomodoro timer** | Standard 25/5 cycles (long break every 4 rounds) with the countdown living inside your notch; automatic break pop-ups with playful messages and selectable system sounds |
| ⏰ **Hourly chime** | A playful time announcement below the notch at the top of every hour; automatically silenced while the screen is locked or asleep |
| 🌤️ **Idle weather** | When nothing else is showing, the notch displays a weather icon with the current temperature (free Open-Meteo data, IP-based location with manual city override) |
| 🎵 **Music + countdown coexistence** | While a Pomodoro session runs, the closed notch shows both the album art and the countdown |
| 🔊 **Sound picker** | Choose from 14 macOS system sounds (with preview) for the Pomodoro reminder and the hourly chime, or mute them |

### 🛠️ Polish

| Fix/improvement | Description |
|---|---|
| 🖱️ **No accidental close on scroll** | Scrolling the notification history, calendar or shelf never triggers the "swipe up to close" gesture |
| 🔐 **Stable permissions** | Stable certificate signing: accessibility, calendar and other grants **survive updates and reinstalls** — no more re-granting |
| 🐛 **Drag-and-drop fix** | Fixes "dragging a file onto the notch does nothing" under the app sandbox (macOS 26) |
| 🚫 **Independent version line** | Detached from the official Sparkle update feed — official releases can never overwrite this fork |

All original features (music controls, calendar, shelf, HUD replacement, camera mirror, …) are fully preserved — see the [original README](https://github.com/TheBoredTeam/boring.notch#readme).

## 📥 Install

1. Grab the latest `boringNotch-*.dmg` from [Releases](https://github.com/y2050802852-ux/boring.notch-plus/releases)
2. Open the DMG and drag **boringNotch.app** into Applications
3. If macOS warns about an unidentified developer: System Settings → Privacy & Security → **Open Anyway** (this project uses a self-signed certificate and is not notarized)

**Requirements**: macOS 14 Sonoma or later · Apple Silicon

> [!NOTE]
> Some features need permission grants: **Accessibility** (notification interception + HUD replacement), Calendar/Reminders (EventKit), Camera (mirror), Apple Events (music/Spotify control); the system asks for clipboard access once when you first use the clipboard history. Denying any of them only disables that specific feature.

## 🛠️ Build from source

- **Xcode 16.0 or later**
- macOS 14+

```bash
git clone https://github.com/y2050802852-ux/boring.notch-plus.git
cd boring.notch-plus
open boringNotch.xcodeproj   # Cmd+R in Xcode
```

Command-line build + DMG packaging:

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination "generic/platform=macOS" build
hdiutil create -volname "boringNotch" \
  -srcfolder ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Release/boringNotch.app \
  -ov -format UDZO boringNotch.dmg
```

> [!NOTE]
> The project sets `ENABLE_HARDENED_RUNTIME` to NO: enabling hardened runtime makes dyld's library validation reject the ad-hoc re-signed embedded MediaRemoteAdapter.framework and the app crashes on launch. Restore it if you sign with a real certificate.

## 📄 License

This project is open-sourced under the [GPL-3.0](LICENSE) license, same as the original.

- Original project copyright © [TheBoredTeam](https://github.com/TheBoredTeam)
- This fork's modifications are likewise contributed back to the community under GPL-3.0

## 🙏 Acknowledgements

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) — the foundation of this project
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) — Now Playing support on macOS 15.4+
- [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) — inspiration for the Shelf feature
- [Open-Meteo](https://open-meteo.com/) — free keyless weather data
- All open-source dependencies listed in [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES)
