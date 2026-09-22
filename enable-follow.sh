#!/bin/zsh
set -eu
app_path='/Applications/Codex Quota.app/Contents/MacOS/CodexQuota'
[[ -x "$app_path" ]] || { print '请先将新版 Codex Quota.app 安装到应用程序目录。'; exit 1; }
agent_path="$HOME/Library/LaunchAgents/local.codex.quota-ring.follow.plist"
mkdir -p "$HOME/Library/LaunchAgents"
cat > "$agent_path" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.codex.quota-ring.follow</string>
<key>ProgramArguments</key><array><string>/Applications/Codex Quota.app/Contents/MacOS/CodexQuota</string></array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)/local.codex.quota-ring.follow" 2>/dev/null || true
pkill -x CodexQuota || true
launchctl bootstrap "gui/$(id -u)" "$agent_path"
