# Codex Quota

原生 macOS 菜单栏额度圆环。双击 `Codex Quota.app` 启动，没有 Dock 图标。

- 实线圆弧代表剩余额度，中心显示剩余百分比。
- 优先显示 300 分钟（5 小时）窗口；只有 10080 分钟（周）窗口时显示周余量，在悬停和详情中说明“周额度”，状态栏不显示文字标签。
- 悬停显示当前窗口重置时间（Mac 本地时区）；点击显示返回的额度窗口、套餐、更新时刻、刷新和退出。
- 每 60 秒读取一次，Mac 唤醒时也会读取。点击“立即刷新”可主动更新。
- 缺失窗口不解释为无限制；无可识别窗口时显示横线。
- 失败保留上次数据，圆弧变淡，悬停和详情显示刷新失败；无历史数据时显示横线。

## 显示与单实例

下拉菜单可切换“圆环样式”和“横条样式”，自动保存选择。横条左侧为加粗数字（无百分号），右侧为 44 pt 长的余量条。重复打开应用会静默退出新进程；通过用户级文件锁保证同一用户仅有一个实例，应用退出或崩溃后系统自动释放锁。

## 数据来源

通过本机 Codex 的 `app-server --listen stdio://`，完成 initialize 后只调用 `account/rateLimits/read`。优先读取 `rateLimitsByLimitId.codex`，兼容 `rateLimits`。使用 Codex 自己维护的登录状态，不读取或保存账号凭证，不消耗重置次数，不发起模型任务。

应用查找 `/Applications/ChatGPT.app/Contents/Resources/codex`、`/Applications/Codex.app/Contents/Resources/codex`、Homebrew 安装路径；也可通过 `CODEX_BINARY` 环境变量指定。需要已登录的 Codex 和网络连接。此 app-server 协议属于当前本机版本提供的实验性接口，升级后可能需要适配。

## 文件与构建

- `Sources/main.swift`：数据模型、只读 JSON-RPC 客户端、菜单栏绘制与详情菜单。
- `build.sh`：使用系统 Swift 编译器构建并做本地 ad-hoc 签名。
- `Codex Quota.app`：已编译的本机应用。

```sh
zsh build.sh
'Codex Quota.app/Contents/MacOS/CodexQuota' --self-test
'Codex Quota.app/Contents/MacOS/CodexQuota' --probe
open 'Codex Quota.app'
```

未设置开机启动。退出可在圆环的详情菜单中操作。

## 本次验证

原生编译、Info.plist 校验、签名验证通过。数据检查涵盖周额度回退、5 小时优先、缺失数据、百分比边界、多额度桶优先级，全部通过。真实额度查询成功，应用进程已启动。桌面控制工具超时，尚未完成菜单栏视觉、hover 和点击详情的屏幕验收。

## PKG 安装包

双击 `CodexQuota-1.0.0-arm64.pkg` 使用系统安装向导，包含介绍、说明、标准安装步骤与完成页面。安装目标为 `/Applications/Codex Quota.app`，支持 Apple Silicon / macOS 14+。安装结束后手动打开应用；若旧版本正在运行，先退出旧版本。本地安装包没有 Developer ID 签名和 Apple 公证。

`Installer/` 保存安装向导资源及配置；运行 `zsh package.sh` 从现有应用生成 PKG。修改源码后先运行 `zsh build.sh`，再运行 `zsh package.sh`。

## 跟随 Codex（本地新版）

监听 `com.openai.codex` 的启动与退出：Codex 运行时显示菜单栏组件并查询额度；完全退出后隐藏组件并停止查询。关闭窗口不等于退出。后台监听进程会保留，以接收下一次启动事件。

将新构建的应用安装到 `/Applications` 后，运行 `zsh enable-follow.sh`，为当前用户启用登录时启动后台监听。退出额度应用会停止本次登录期间的监听；重新打开应用可恢复。

停止登录时后台启动可执行：

```sh
launchctl bootout "gui/$(id -u)/local.codex.quota-ring.follow"
rm "$HOME/Library/LaunchAgents/local.codex.quota-ring.follow.plist"
```

此前发布的 1.0.0 PKG 尚不包含此功能。
