# boring.notch 源码架构笔记（二次开发参考）

> 基于 2.7.3 源码快照整理（工程实际版本号 **2.7.2 / build 262**，与文件夹名不一致）。
> 面向目标：本地二次开发、修改源码后重新编译出 .app / DMG。

---

## 1. 项目概览

boring.notch 是一个 macOS **刘海增强工具**（SwiftUI + AppKit 混合，最低系统 macOS 14）：
把 Mac 的刘海变成音乐控制中心（可视化律动、歌词、专辑封面），外加日历/提醒、文件 Shelf（支持 AirDrop）、系统 HUD 替换（音量/亮度/背光）、摄像头镜像、电池状态等。

- 主 App：`boringNotch.app`（Bundle ID `theboringteam.boringnotch`，App 沙盒开启，`LSUIElement` 菜单栏应用）
- 内嵌 XPC 服务：`BoringNotchXPCHelper.xpc`（非沙盒，负责辅助功能授权 + 亮度/背光私有框架调用）
- 内嵌预编译二进制：`MediaRemoteAdapter.framework`（读 Now Playing 用，macOS 15.4+ 唯一可行路径）

---

## 2. 工程结构与 Targets

```
boring.notch-2.7.3/
├── boringNotch.xcodeproj/        # 工程文件（objectVersion 70，Xcode 15.4+）
├── boringNotch/                  # 主 App 全部源码（123 个 Swift 文件）
│   ├── boringNotchApp.swift      # @main 入口 + AppDelegate（窗口管理核心）
│   ├── ContentView.swift         # 刘海主视图（关闭/展开所有状态）
│   ├── BoringViewCoordinator.swift # 全局 UI 协调单例（当前 Tab、sneak peek 等）
│   ├── components/               # SwiftUI 组件（Notch/Music/Shelf/Settings/Calendar/...）
│   ├── managers/                 # 业务管理器（MusicManager/CalendarManager/VolumeManager/...）
│   ├── models/                   # BoringViewModel（每屏一个）+ 数据模型 + Constants.swift
│   ├── MediaControllers/         # 四种音乐源控制器（协议 MediaControllerProtocol）
│   ├── XPCHelperClient/          # XPC 客户端
│   ├── observers/                # DragDetector / MediaKeyInterceptor / FullscreenMediaDetection
│   ├── private/CGSSpace.swift    # 私有 CGS API（@_silgen_name）
│   ├── sizing/matters.swift      # 所有尺寸常量（single source of truth）
│   ├── animations/ enums/ extensions/ helpers/ utils/ menu/ Shortcuts/
│   └── Info.plist / boringNotch.entitlements
├── BoringNotchXPCHelper/         # XPC 服务 target（main.swift + BoringNotchXPCHelper.swift）
├── mediaremote-adapter/          # 预编译二进制（不参与编译，直接打包进 Resources/Frameworks）
│   ├── MediaRemoteAdapter.framework
│   ├── MediaRemoteAdapterTestClient
│   └── mediaremote-adapter.pl
├── updater/appcast.xml           # Sparkle 更新源（repo 副本，CI 重新生成）
├── Configuration/sparkle/generate_appcast  # 预编译的 Sparkle 工具（CI 用）
└── .github/workflows/            # release.yml = 官方发布流水线（本地构建的参考）
```

**两个 Target：**

| | boringNotch（App） | BoringNotchXPCHelper（XPC） |
|---|---|---|
| Bundle ID | `theboringteam.boringnotch` | `theboringteam.boringnotch.BoringNotchXPCHelper` |
| 最低系统 | macOS 14.0 | macOS 15.5 |
| 沙盒 | ✅ 开启 | ❌ 关闭（故意的） |
| 签名 | 仓库里是 ad-hoc（`CODE_SIGN_IDENTITY[sdk=macosx*] = "-"`），`DEVELOPMENT_TEAM` 为空 | 同左 |

App target **依赖** XPC target 并有 "Embed XPC Services" 拷贝阶段（装入 `Contents/XPCServices`）；另有 "Embed Frameworks" 阶段把 `MediaRemoteAdapter.framework` 重签名后装入 `Contents/Frameworks`。**没有任何 Run Script 构建阶段**，本地构建不需要手动跑额外脚本。

---

## 3. SPM 依赖（全部远程包）

| 包 | 用途 |
|---|---|
| Sparkle 2.8.0 | 自动更新 |
| sindresorhus/Defaults 9.x | 设置持久化（约 70 个 key，见 `models/Constants.swift`） |
| sindresorhus/KeyboardShortcuts | 全局快捷键 |
| sindresorhus/LaunchAtLogin-Modern | 登录启动 |
| apple/swift-collections | 数据结构 |
| siteline/swiftui-introspect | SwiftUI 内省 |
| Lakr233/SkyLightWindow | 私有 SkyLight API（锁屏时窗口置顶） |
| airbnb/lottie-spm | Lottie 动画（自定义可视化） |
| ChimeHQ/AsyncXPCConnection | XPC 异步封装 |
| TheBoredTeam/MacroVisionKit | 自家工具包（MediaRemote 私有框架封装 + 全屏监控） |
| Pow（只声明未链接，遗留物） | — |

---

## 4. 启动与窗口架构（最核心的机制）

**入口** `boringNotch/boringNotchApp.swift`：SwiftUI `App` 里没有 WindowScene，只有一个 `MenuBarExtra`（菜单栏星形图标 + 设置/退出）。**刘海窗口完全由 AppDelegate 用 AppKit 手工创建**。

关键流程：
1. `AppDelegate.createBoringNotchWindow(for:with:)` 创建 `BoringNotchSkyLightWindow`（`NSPanel` 子类，`components/Notch/BoringNotchSkyLightWindow.swift`）：
   - styleMask `[.borderless, .nonactivatingPanel, .utilityWindow, .hudWindow]`，透明背景、无阴影、不可成为 key window
   - `level = .mainMenu + 3`，顶部居中定位（`screen.frame.maxY - height`）
   - `collectionBehavior = [.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`
   - contentView = `NSHostingView(rootView: ContentView())`
2. 窗口被塞进 `NotchSpaceManager` 管理的 **私有 CGS Space**（`private/CGSSpace.swift`，`@_silgen_name` 私有 API，level = Int.max）→ 不激活 App、悬浮在所有桌面/全屏之上。
3. 多显示器：按屏幕 displayUUID 建多套 `windows: [String: NSWindow]` + `viewModels: [String: BoringViewModel]` 字典。
4. 窗口尺寸固定为 `windowSize = openNotchSize(640×190) + shadowPadding(20)`，**永不改变**；只改 SwiftUI 内容高度 + "chin" 矩形宽度。
5. 锁屏时通过 SkyLightWindow 包把窗口委托进锁屏 Space（dlopen SkyLight.framework）。
6. 系统事件：`DistributedNotificationCenter` 监听锁屏/解锁；全局 `DragDetector`（NSEvent monitor + 拖拽剪贴板检查）检测到拖文件到刘海区域 → 自动展开切到 Shelf Tab。

**重新布局** `adjustWindowPosition(changeAlpha:)` 是总闸：屏幕变化、刘海高度设置变化等通过 Notification 通知（`selectedScreenChanged`、`notchHeightChanged` 等，定义在 boringNotchApp.swift 底部）触发。

---

## 5. UI 层

### 5.1 ContentView 结构（`boringNotch/ContentView.swift`）

一个 `VStack`：**NotchLayout（黑色圆角主体）+ Chin（透明延伸区，用于加宽）**。

- 展开动画：open `spring(0.42, 0.8)` / close `spring(0.45, 1.0)` / 交互 `interactiveSpring(0.38, 0.8)`（分散写死在 ContentView/NotchHomeView，`animations/drop.swift` 里的 BoringAnimations 基本没被用）
- 交互：hover 延迟自动展开（`Defaults[.minimumHoverDuration]`）、点击展开、上下 pan 手势、触觉反馈
- **关闭状态内容切换**（NotchLayout 内一长串 if/else）：电池展开视图 → 内联 HUD → 音乐 Live Activity（专辑图 + 跑马灯 + 律动条/Lottie）→ 人脸动画（闲置时）→ 首次启动 hello 动画
- **展开状态**：`BoringHeader`（左 Tab 选择器 / 中间黑色矩形精确遮住真刘海让硬件刘海透出 / 右摄像头+设置+电池）→ `switch coordinator.currentView`：`.home` = `NotchHomeView`（音乐播放器 + 日历 + 摄像头），`.shelf` = `ShelfView`

### 5.2 尺寸模型（`boringNotch/sizing/matters.swift`）

- `openNotchSize = 640×190`（写死）；圆角 `cornerRadiusInsets = (opened: top 19 / bottom 24, closed: top 6 / bottom 14)`
- 关闭态宽度 = 真刘海宽度：`screen.frame.width - auxiliaryTopLeftArea - auxiliaryTopRightArea + 4`（+4 是像素对齐魔法数）；非刘海屏硬编码 185
- 关闭态高度三种模式（`notchHeight`）：matchRealNotchSize / matchMenuBar / custom；非刘海屏用 `nonNotchHeight`（默认 32）
- ⚠️ **改关闭尺寸必须同步改**：`BoringHeader` 的黑色遮罩宽度、`computedChinWidth`、`effectiveClosedNotchHeight` 相关的 Live Activity 布局公式，否则刘海"接缝"会露出来

### 5.3 设置界面

`components/Settings/SettingsWindowController.swift`（单例 NSWindow 700×600，显示时把 App 激活策略从 `.accessory` 切到 `.regular`，关闭切回）+ `SettingsView.swift`（1774 行，NavigationSplitView）：General / Appearance / Media / Calendar / HUDs / Battery / Shelf / Shortcuts / Advanced / About 十个页面。

### 5.4 状态管理

- `BoringViewModel`（`models/BoringViewModel.swift`）：**每屏一个**，持有 notchState、notchSize、拖拽定位标志、open()/close()（close 受 `SharingStateManager.preventNotchClose` 阻断保护）
- `BoringViewCoordinator`（单例）：currentView（home/shelf）、sneakPeek（音量/亮度/音乐等胶囊提示，带自动隐藏 Task）、expandingView（电池/音乐 chin 展开）、多个 @AppStorage

---

## 6. 业务逻辑层

### 6.1 音乐播放（最重要的子系统）

四种可互换的音乐源，实现 `MediaControllerProtocol`（`MediaControllers/MediaControllerProtocol.swift`：playbackStatePublisher + play/pause/seek/volume/favorite 等）：

| 控制器 | 读取 | 控制 | 备注 |
|---|---|---|---|
| `NowPlayingController` | spawn `/usr/bin/perl mediaremote-adapter.pl <framework> stream` 读 JSON Lines | 直接 dlopen **MediaRemote.framework** 发 `MRMediaRemoteSendCommand`（0播放1暂停2切换4下一首5上一首） | macOS 15.4+ 私有 API 被砍，`MediaChecker` 运行时探测（跑 TestClient，exit 1 = 已废弃） |
| `AppleMusicController` | AppleScript + `com.apple.Music.playerInfo` 分布式通知 | AppleScript | 一次脚本返回 11 个字段 |
| `SpotifyController` | AppleScript + `com.spotify.client.PlaybackStateChanged` | AppleScript | 封面按 URL 异步拉取 |
| `YouTubeMusicController` | HTTP/WS 客户端连 pear-desktop 版 YT Music App 本地 API（`localhost:26538`，Bearer token 经 `POST /auth/boringNotch`） | 同左 | 纯网络协议，无私有框架 |

`MusicManager`（单例，`managers/MusicManager.swift`）订阅 activeController 的 playbackStatePublisher，diff 成 published UI 状态（标题/艺术家/封面 NSImage/avgColor/进度/歌词...）。歌词：Apple Music 走 AppleScript，其余走 LRCLIB Web API。进度靠 `estimatedPlaybackPosition(at:)` 外推（TimelineView）。

**⚠️ 换签名/改 Bundle ID 时必须保留** `mediaremote-adapter.pl`（Resources）、`MediaRemoteAdapterTestClient`（Resources）、`MediaRemoteAdapter.framework`（Frameworks），否则 Now Playing 全挂。

### 6.2 HUD 替换（音量/亮度/键盘背光）

- **拦截**：`observers/MediaKeyInterceptor.swift` 用 CGEventTap（`CGEventType(rawValue: 14)`，系统定义事件类型）截获 F1-F3/媒体键 → **需要辅助功能权限**
- **权限**：辅助功能授权走 XPC Helper（`AXIsProcessTrusted` 在非沙盒 helper 里执行）；新授权后必须**重启 App** 才能加 tap（`ApplicationRelauncher.restart()`）
- **状态**：`VolumeManager`（CoreAudio 监听默认输出设备音量/静音）、`BrightnessManager`/`KeyboardBacklightManager`（实际 get/set 全部委托给 XPC Helper 的私有框架 CoreBrightness/DisplayServices）
- **渲染**：HUD 就是刘海窗口里的 sneakPeek 视图（`components/Live activities/SystemEventIndicatorModifier.swift` + `InlineHUD.swift`，可拖动滑条直接改音量/亮度）

### 6.3 Shelf（文件架 + AirDrop）

`components/Shelf/` 完整分层：Models（ShelfItem = file(bookmark)/text/link）→ Services（`ShelfPersistenceService` 持久化到 `~/Library/Application Support/boringNotch/Shelf/items.json`；`ShelfDropService` 处理 NSItemProvider；`QuickShareService` 运行时发现 NSSharingService、AirDrop 固定排第一）→ ViewModels（`ShelfStateViewModel` 单例，去重/书签校验/延迟刷新避免 view update 崩溃）→ Views。
拖入：全局 `DragDetector` 检测 → 展开刘海切到 Shelf；拖出：`ShelfItemView` 里的 `DraggableClickView`（NSDraggingSource）发起 AppKit 拖拽 + 安全作用域书签访问。
分享期间 `SharingStateManager.preventNotchClose` 引用计数阻止刘海自动关闭。

### 6.4 日历/提醒

`CalendarManager`（单例）+ `Providers/CalendarServiceProviding.swift`（封装单个 EKEventStore，macOS 14+ 的 `requestFullAccessToEvents/Reminders`）。订阅 `EKEventStoreChanged`，选择状态存 `Defaults[.calendarSelectionState]`，提醒完成状态写回 EventKit。

### 6.5 其他

- **摄像头镜像**：`WebcamManager`（AVCaptureSession 专用串行队列，停止时彻底 teardown 保隐私）+ `WebcamView`（AVCaptureVideoPreviewLayer 镜像渲染）
- **电池**：`BatteryActivityManager`（IOKit power sources 通知）→ `BatteryStatusViewModel` → 触发 chin 展开视图
- **全屏隐藏**：`FullscreenMediaDetector`（MacroVisionKit FullScreenMonitor），"仅媒体全屏时隐藏"用 bundleIdentifier 匹配
- **摄像头预览权限**：`BoringViewModel.toggleCameraPreview()` 完整处理 notDetermined/denied（弹窗 + 深链系统设置）

---

## 7. 设置持久化（⚠️ 两个存储命名空间）

1. **Defaults 包**（UserDefaults 封装）：约 70 个 key 集中在 `models/Constants.swift`
2. **原生 @AppStorage**（在 `BoringViewCoordinator`）：firstLaunch、musicLiveActivityEnabled、alwaysShowTabs、preferred_screen_uuid 等

改设置项时两边都要查。快捷键定义在 `Shortcuts/ShortcutConstants.swift`（部分定义了但未接线，如剪贴板历史 ⇧⌘C、麦克风 F5）。

---

## 8. XPC Helper（HUD 替换专用）

- 进程模型：**嵌入式 XPC Service**（`Contents/XPCServices`，launchd 按需拉起），**不是** SMJobBless/LaunchDaemon
- 协议：`BoringNotchXPCHelperProtocol.swift`（App/Helper 两边各有一份拷贝，改了要同步）
- 能力：辅助功能检查/弹授权（TCC 记录挂在 helper 名下）、键盘背光（私有 CoreBrightness `KeyboardBrightnessClient`）、屏幕亮度（私有 DisplayServices + IOKit 兜底）
- 客户端：`XPCHelperClient/XPCHelperClient.swift`，mach service 名 `theboringteam.boringnotch.BoringNotchXPCHelper`，连接失败全部优雅降级为 false 并自动关闭 hudReplacement

---

## 9. Entitlements 与权限

App（`boringNotch/boringNotch.entitlements`）：
- 沙盒 ✅，Apple Events 自动化、摄像头、日历
- 书签：app-scope + document-scope；用户选文件读写
- 网络 client + server
- **temporary-exception.apple-events**：`com.spotify.client`、`com.apple.Music`（App Store 不会批这种例外 —— 自建分发没问题，上 MAS 会废掉 Spotify/Apple Music AppleScript 控制）
- temporary-exception.mach-lookup：Sparkle 的 `-spks`/`-spki`

Info.plist：`SUFeedURL = https://TheBoredTeam.github.io/boring.notch/appcast.xml`、`SUPublicEDKey = B1Y47t8C/...`、ATS `NSAllowsArbitraryLoads = true`（封面 URL 需要）。

预期会弹的权限：辅助功能（走 helper，授权后自动重启）、摄像头、日历+提醒完全访问、Apple Events（Music/Spotify）。

---

## 10. 本地重编译 → DMG（承接上次会话的目标）

```bash
cd /Users/imac/codes/Source_codes/boring.notch-2.7.3

# 1. 解析 SPM 依赖（需联网，约 11 个包）
xcodebuild -resolvePackageDependencies -project boringNotch.xcodeproj

# 2. Release 构建 —— 仓库默认 ad-hoc 签名，无需开发者账号
xcodebuild -project boringNotch.xcodeproj \
  -scheme boringNotch \
  -configuration Release \
  -destination "generic/platform=macOS" \
  build
# 产物在 DerivedData 下 Build/Products/Release/boringNotch.app
# (scheme 未入库，xcodebuild 会自动生成；不行就先 open 工程一次)

# 3. 打 DMG（官方 CI 同款命令）
hdiutil create -volname "boringNotch 2.7.2" \
  -srcfolder <构建产物路径>/boringNotch.app \
  -ov -format UDZO boringNotch.dmg
```

要点：
- **无需任何手动脚本**：XPC helper 自动嵌入、framework 自动重签（CodeSignOnCopy）
- `mediaremote-adapter` 是**预编译二进制**，不参与编译，直接打包
- 官方 CI（`.github/workflows/release.yml`）流程：注入证书 → sed 改 pbxproj 里的版本号 → `xcodebuild archive`（Development 签名，**无公证**）→ hdiutil 打 DMG → `generate_appcast`（私钥签名）发 Release
- **Sparkle 更新**：本地构建会连官方 appcast；自用 fork 建议改掉 `SUFeedURL` 或删掉 `SPUStandardUpdaterController`，否则可能被"更新"回官方版本覆盖修改
- 本机工具链 Swift 6.3.3 可用；工程是 Swift 5 语言模式 + targeted concurrency，新编译器可能有新告警

---

## 11. 二次开发注意事项（坑清单）

1. **私有 API 三处**：CGSSpace.swift（`@_silgen_name`）、SkyLightWindow（锁屏置顶）、MediaRemote（Now Playing）+ XPC Helper 里的 CoreBrightness/DisplayServices。系统大版本更新可能断裂，`MediaChecker` 已有运行时探测先例可参考。
2. **多窗口架构**：每个显示器一套 window+viewModel，写新功能别假设单例刘海。
3. **关闭保护链**：分享中（preventNotchClose）、电池弹窗、日历 hover 都会阻止自动关闭——在刘海里加新交互 UI 要记得扩展这些 guard，否则会被自动关闭打断。
4. **激活策略舞蹈**：Settings/Onboarding 窗口显示时切 `.regular`，关闭切回 `.accessory`。新建 key window 要复刻。
5. **改关闭尺寸三联动**：matters.swift + BoringHeader 黑色遮罩 + computedChinWidth/effectiveClosedNotchHeight 公式。
6. **设置双存储**：Constants.swift 的 Defaults keys 和 Coordinator 的 @AppStorage。
7. **协议双拷贝**：`BoringNotchXPCHelperProtocol.swift` 在两个 target 各一份。
8. **死代码**（可无视或清理）：`BoringNotchWindow.swift`（旧窗口类）、`BoringExtrasMenu.swift`、`menu/StatusBarMenu.swift`、`TestView.swift`、`WhatsNewView.swift`、`Tips/TipStore.swift`、注释掉的 Downloads/Extensions 设置页、Pow 包引用。
9. **硬编码值**：YT Music 端口 26538、音量/亮度步长 1/16、sneak peek 时长 1.5s/3s、刘海宽度 +4 魔法数。
10. **版本号**：工程实际 2.7.2(262)，改版号直接改 pbxproj 的 MARKETING_VERSION / CURRENT_PROJECT_VERSION。
