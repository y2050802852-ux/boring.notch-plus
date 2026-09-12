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
> 本项目是 [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch) 的**二次开发版（fork）**，原项目采用 **GPL-3.0 许可证**，本仓库延续相同许可证开源。所有核心功劳归于 [TheBoredTeam](https://github.com/TheBoredTeam) 原作者与贡献者，本项目在其基础上新增了若干功能。

## ✨ 相比原版的新增功能

| 功能 | 说明 |
|---|---|
| 🍅 **番茄时钟** | 标准 25/5 循环（每 4 轮长休），倒计时直接显示在刘海里；阶段结束自动弹出休息提醒页 + 可选音效；专注/休息俏皮话随机提醒 |
| ⏰ **整点报时** | 每个整点在刘海下方弹出俏皮报时语；锁屏/睡眠自动静默 |
| 🌤️ **闲置天气** | 刘海完全闲置时显示天气图标 + 当前温度（Open-Meteo 免费数据，IP 自动定位，支持手动搜索城市修正） |
| 🗑️ **暂存区一键清空** | 暂存区（Shelf）右上角垃圾桶按钮，一键移除所有条目（原文件永不删除） |
| 🎵 **音乐 + 倒计时共存** | 番茄钟运行时收起态刘海同时显示专辑封面与倒计时，互不遮挡 |
| 🔊 **音效选择器** | 番茄钟/整点报时各自可选 14 种 macOS 系统音效（带试听），或静音 |
| 🐛 **拖拽入库修复** | 修复了沙盒环境下"拖文件到刘海无反应"的问题（macOS 26） |
| 🚫 **独立版本线** | 已脱离官方 Sparkle 更新源，不会被官方版本覆盖 |

原版功能（音乐控制、日历、暂存区、HUD 替换、摄像头镜像等）全部保留，详见[原项目 README](https://github.com/TheBoredTeam/boring.notch#readme)。

## 📥 安装

1. 前往 [Releases](https://github.com/y2050802852-ux/boring.notch-plus/releases) 下载最新的 `boringNotch-1.0.0.dmg`
2. 打开 DMG，将 **boringNotch.app** 拖入「应用程序」
3. 首次启动若提示"来自未知开发者"：系统设置 → 隐私与安全性 → **仍要打开**（本项目为 ad-hoc 签名，无开发者账号）

**系统要求**：macOS 14 Sonoma 或更高 · Apple Silicon（M 系列芯片）

> [!NOTE]
> 部分功能需要授权：日历/提醒事项（读写 EventKit）、摄像头（镜像）、辅助功能（HUD 替换）、Apple Events（控制音乐/Spotify）。拒绝授权不影响其他功能使用。

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
  -configuration Release -destination "generic/platform=macOS" \
  ENABLE_HARDENED_RUNTIME=NO build
hdiutil create -volname "boringNotch" \
  -srcfolder ~/Library/Developer/Xcode/DerivedData/boringNotch-*/Build/Products/Release/boringNotch.app \
  -ov -format UDZO boringNotch.dmg
```

> [!NOTE]
> `ENABLE_HARDENED_RUNTIME=NO` 是本地 ad-hoc 签名的关键：开启硬化运行时会导致 dyld 库验证拒绝 ad-hoc 重签名的内嵌 MediaRemoteAdapter.framework，应用启动即崩。用真证书签名时可以去掉。

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
