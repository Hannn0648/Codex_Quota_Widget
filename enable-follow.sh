#!/bin/zsh
set -eu
agent_path=/Library/LaunchAgents/local.codex.quota-ring.follow.plist
[[ -f "$agent_path" ]] || { print '请先安装新版 PKG。 / Install the current PKG first.'; exit 1; }
launchctl bootout "gui/$(id -u)/local.codex.quota-ring.follow" 2>/dev/null || true
pkill -x CodexQuota || true
launchctl bootstrap "gui/$(id -u)" "$agent_path"
