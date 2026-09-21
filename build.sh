#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p 'Codex Quota.app/Contents/MacOS'
swiftc -O Sources/main.swift -o 'Codex Quota.app/Contents/MacOS/CodexQuota' -framework AppKit
cat > 'Codex Quota.app/Contents/Info.plist' <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CodexQuota</string>
<key>CFBundleIdentifier</key><string>local.codex.quota-ring</string>
<key>CFBundleName</key><string>Codex Quota</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - 'Codex Quota.app'
