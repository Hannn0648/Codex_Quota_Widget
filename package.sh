#!/bin/zsh
set -eu
cd "$(dirname "$0")"
source ./version.env
zsh build.sh
package_work=$(mktemp -d "${TMPDIR:-/tmp}/codex-quota-package.XXXXXX")
trap 'rm -rf "$package_work"' EXIT
mkdir -p "$package_work/root/Applications" "$package_work/root/Library/LaunchAgents"
ditto 'Codex Quota.app' "$package_work/root/Applications/Codex Quota.app"
cp Installer/local.codex.quota-ring.follow.plist "$package_work/root/Library/LaunchAgents/"
sed "s/@APP_VERSION@/$APP_VERSION/g" Installer/Distribution.xml > "$package_work/Distribution.xml"
pkgbuild --root "$package_work/root" --component-plist Installer/components.plist --scripts Installer/Scripts --identifier local.codex.quota-ring.installer --version "$APP_VERSION" --install-location / "$package_work/CodexQuota-component.pkg"
productbuild --distribution "$package_work/Distribution.xml" --resources Installer/Resources --package-path "$package_work" "CodexQuota-${APP_VERSION}-arm64.pkg"
