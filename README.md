# Codex Quota

<img src="Assets/AppIcon.png" alt="Codex Quota icon / 应用图标" width="160" height="160">

## 介绍 / Introduction

在 macOS 菜单栏查看 Codex 剩余额度，支持圆环与横条样式、悬停查看重置时间。跟随 Codex 启停：运行时显示额度，完全退出后隐藏并停止查询。

View remaining Codex quota in the macOS menu bar, with ring and bar styles and reset-time tooltips. The indicator appears while Codex runs, then hides and stops querying when Codex fully quits.

## 安装 / Installation

双击 `CodexQuota-1.1.0-arm64.pkg`，按系统向导安装。应用位于 `/Applications/Codex Quota.app`，安装后自动启动后台监听，并在登录时启动；若未启动，从“应用程序”打开 Codex Quota。

Open `CodexQuota-1.1.0-arm64.pkg` and follow the installer. The app installs to `/Applications/Codex Quota.app`. Its background listener starts after installation and at login; if needed, open Codex Quota from Applications.

## 注意事项 / Notes

- 需要 Apple Silicon、macOS 14+，以及已安装并登录的 Codex 和网络连接。

  Requires Apple Silicon, macOS 14+, an installed and logged-in Codex, and network access.

- 关闭 Codex 窗口不等于退出。退出额度应用会停止监听，重新打开或重新登录可恢复。

  Closing a Codex window does not quit it. Quitting the quota app stops its listener; reopen it or log in again to resume.

- 旧版 1.0.0 PKG 不包含启停跟随、新图标和登录启动，请使用 1.1.0。升级会重启当前登录用户的额度进程；其他已登录用户需重新打开应用或重新登录。

  The old 1.0.0 PKG lacks lifecycle following, the new icon, and login startup. Use 1.1.0. Upgrading restarts the console user's quota process; other active users should reopen the app or log in again.

- 应用采用 ad-hoc 签名，安装包没有 Developer ID 签名或 Apple 公证。额度接口属于 Codex 的实验性接口，后续更新可能需要适配。

  The app is ad-hoc signed; the package has no Developer ID signature or Apple notarization. The quota interface is experimental and may require adaptation after Codex updates.
