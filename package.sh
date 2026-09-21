#!/bin/zsh
set -eu
cd "$(dirname "$0")"
package_work=$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-package.XXXXXX")
trap 'rm -rf "$package_work"' EXIT
mkdir -p "$package_work/root"
ditto 'Codex Quota.app' "$package_work/root/Codex Quota.app"
pkgbuild --root "$package_work/root" --component-plist Installer/components.plist --identifier local.codex.quota-ring.installer --version 1.0.0 --install-location /Applications "$package_work/CodexQuota-component.pkg"
productbuild --distribution Installer/Distribution.xml --resources Installer/Resources --package-path "$package_work" CodexQuota-1.0.0-arm64.pkg
