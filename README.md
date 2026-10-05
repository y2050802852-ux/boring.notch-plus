<h1 align="center">boring.notch-plus</h1>

<p align="center">
  <strong>中文</strong> · <a href="README_EN.md">English</a>
</p>

<p align="center">
  一款让你的 MacBook 刘海变成效率中心的 macOS 应用 —— 在出色的
  <a href="https://github.com/TheBoredTeam/boring.notch">TheBoredTeam/boring.notch</a>
  基础上的二次开发增强版。
</p>

> [!IMPORTANT]
> 本项目是 [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) 的**二次开发版（fork）**，原项目采用 **GPL-3.0 许可证**，本仓库延续相同许可证开源。所有核心功劳归于 [TheBoredTeam](https://github.com/TheBoredTeam) 原作者与贡献者，本项目在其基础上新增了大量功能。

## ✨ 相比原版的新增功能

### 📢 通知替代（核心新功能）

| 功能 | 说明 |
|---|---|
| 📥 **横幅拦截转写** | 第三方应用的通知自动转写进刘海——刘海向下展开弹窗显示应用图标、标题与正文，右上角的系统横幅不再打扰；通知仍会保留在系统通知中心列表里 |
| 🚫 **系统通知全部屏蔽** | 「软件更新」「时钟」「系统设置」「屏幕使用时间」等系统应用的横幅直接隐藏——刘海**只弹第三方应用等非系统通知**；系统授权弹窗（日历、辅助功能等）完全不受影响 |
| 🕘 **通知历史** | 点击刘海里的 🔔 标签随时回看最近通知，支持一键清空 |
| 🖼️ **真实应用图标** | 弹窗与历史列表显示发送应用的真实图标（如微信通知显示微信图标） |
| 👆 **点击打开应用** | 点击弹窗或历史条目，直接激活/启动发送该通知的应用 |
| 📏 **动态宽度** | 短通知几乎与刘海等宽，长通知加宽到上限后自动折行，不再整条拉伸占满屏幕 |
| 🔇 **静音名单** | 不想被打扰的应用加入静音名单——不弹窗但保留在历史里；支持在历史列表一键静音 |

> [!NOTE]
> 通知替代需在 设置 → 通知 中开启并授予辅助功能权限。原生闹钟的全屏弹窗不经过通知中心，无法拦截（系统限制）。

### 📋 剪贴板历史

| 功能 | 说明 |
|---|---|
| 📋 **自动记录** | 复制的**文字与图片**自动进入历史；点击刘海**右上角的剪贴板图标**查看列表 |
| 👆 **点击回填** | 点击任意条目回填剪贴板（条目上出现 ✓），到任何地方 ⌘V 粘贴 |
| 💾 **磁盘持久化** | 重启应用/电脑后历史仍在；默认保留 50 条（10–200 可调），满了自动淘汰最旧的 |
| 🔒 **隐私红线** | 密码管理器标记为隐藏的内容（1Password、Bitwarden 等）**永不记录**；可随时一键清空全部历史 |
| ⌨️ **全局快捷键** | 默认 **⌘⇧C** 直接打开剪贴板面板，再按一次关闭；可在 设置 → 快捷键 自定义 |

### 🍅 效率增强（此前版本）

| 功能 | 说明 |
|---|---|
| 🍅 **番茄时钟** | 标准 25/5 循环（每 4 轮长休），倒计时直接显示在刘海里；阶段结束自动弹出休息提醒页 + 可选音效；专注/休息俏皮话随机提醒 |
| ⏰ **整点报时** | 每个整点在刘海下方弹出俏皮报时语；锁屏/睡眠自动静默 |
| 🌤️ **闲置天气** | 刘海完全闲置时显示天气图标 + 当前温度（Open-Meteo 免费数据，IP 自动定位，支持手动搜索城市修正） |
| 🎵 **音乐 + 倒计时共存** | 番茄钟运行时收起态刘海同时显示专辑封面与倒计时，互不遮挡 |
| 🔊 **音效选择器** | 番茄钟/整点报时各自可选 14 种 macOS 系统音效（带试听），或静音 |

### 🛠️ 体验优化

| 修复/优化 | 说明 |
|---|---|
| 🖱️ **滚动不误关** | 在通知历史、日历、暂存区等可滚动区域滚动时，不会误触发"上滑关闭刘海"手势 |
| 🔐 **授权稳定** | 稳定证书签名：升级 / 重新安装后辅助功能、日历等授权**不再丢失**，无需反复重新授权 |
| 🐛 **拖拽入库修复** | 修复了沙盒环境下"拖文件到刘海无反应"的问题（macOS 26） |
| 🚫 **独立版本线** | 已脱离官方 Sparkle 更新源，不会被官方版本覆盖 |

原版功能（音乐控制、日历、暂存区、HUD 替换、摄像头镜像等）全部保留，详见[原项目 README](https://github.com/TheBoredTeam/boring.notch#readme)。

## 📥 安装

1. 前往 [Releases](https://github.com/y2050802852-ux/boring.notch-plus/releases) 下载最新版本的 `boringNotch-*.dmg`
2. 打开 DMG，将 **boringNotch.app** 拖入「应用程序」
3. 首次启动若提示"来自未知开发者"：系统设置 → 隐私与安全性 → **仍要打开**（本项目使用自签名证书，未经公证）

**系统要求**：macOS 14 Sonoma 或更高 · Apple Silicon（M 系列芯片）

> [!NOTE]
> 部分功能需要授权：**辅助功能**（通知拦截 + HUD 替换）、日历/提醒事项（EventKit）、摄像头（镜像）、Apple Events（控制音乐/Spotify）；首次使用剪贴板历史时系统会弹一次剪贴板访问确认。拒绝授权不影响其他功能使用。

## 🛠️ 从源码构建

- **Xcode 16.0 或更高版本**
- macOS 14+

```bash
git clone https://github.com/y2050802852-ux/boring.notch-plus.git
cd boring.notch-plus
open boringNotch.xcodeproj   # Xcode 中 Cmd+R 运行
```

命令行构建 + 打包 DMG：

```bash
xcodebuild -project boringNotch.xcodeproj -scheme boringNotch \
  -configuration Release -destination "generic/platform=macOS" build
hdiutil create -volname "boringNotch" \
  -srcfolder ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Release/boringNotch.app \
  -ov -format UDZO boringNotch.dmg
```

> [!NOTE]
> 工程已将 `ENABLE_HARDENED_RUNTIME` 设为 NO：开启硬化运行时会导致 dyld 库验证拒绝 ad-hoc 重签名的内嵌 MediaRemoteAdapter.framework，应用启动即崩。改用真证书签名时可恢复。

## 📄 许可证

本项目基于 [GPL-3.0](LICENSE) 许可证开源，与原项目保持一致。

- 原项目版权 © [TheBoredTeam](https://github.com/TheBoredTeam)
- 本 fork 的修改部分同样以 GPL-3.0 向社区开放

## 🙏 致谢

- [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) —— 本项目的基础
- [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) —— macOS 15.4+ 的 Now Playing 支持
- [Lakr233/NotchDrop](https://github.com/Lakr233/NotchDrop) —— Shelf 功能的灵感来源
- [Open-Meteo](https://open-meteo.com/) —— 免费无 key 的天气数据
- 以及 [THIRD_PARTY_LICENSES](THIRD_PARTY_LICENSES) 中列出的所有开源依赖
