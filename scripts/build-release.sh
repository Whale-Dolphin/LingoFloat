#!/usr/bin/env bash
# Build an arm64 Release app, ad-hoc sign it, and package a distributable DMG.
#
# Usage: ./scripts/build-release.sh 1.1.0
# Output:
#   build/LingoFloat-1.1.0.dmg
#   build/LingoFloat-1.1.0.dmg.sha256
#
# This repository does not require an Apple Developer certificate. The
# resulting app is integrity-signed but not notarized, so first launch uses
# macOS Privacy & Security -> Open Anyway. See Docs/dmg-readme.txt.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>   e.g. $0 1.1.0" >&2
  exit 2
fi

version="$1"
if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
  echo "ERROR: version must be SemVer (X.Y.Z or X.Y.Z-suffix). Got: $version" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
project="$project_root/LingoFloat/LingoFloat.xcodeproj"
entitlements="$project_root/LingoFloat/LingoFloat.entitlements"
local_config="$project_root/LingoFloat/Local.xcconfig"
build_dir="$project_root/build"
source_packages="$project_root/.build/SourcePackages"
xcode_dir="${LINGOFLOAT_XCODE_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
dmg_name="LingoFloat-$version.dmg"
dmg_path="$build_dir/$dmg_name"
checksum_path="$dmg_path.sha256"

if [[ ! -d "$xcode_dir" ]]; then
  echo "ERROR: Xcode developer directory not found: $xcode_dir" >&2
  echo "Set LINGOFLOAT_XCODE_DIR to Xcode.app/Contents/Developer." >&2
  exit 1
fi

if [[ ! -f "$local_config" ]]; then
  cp "$project_root/LingoFloat/Local.xcconfig.template" "$local_config"
fi

mkdir -p "$build_dir" "$source_packages"
work_dir="$(mktemp -d "$build_dir/.release-$version.XXXXXX")"
cleanup() {
  if [[ -d "$work_dir" ]]; then
    find "$work_dir" -depth -delete
  fi
}
trap cleanup EXIT

derived_data="$work_dir/DerivedData"
staging="$work_dir/dmg-staging"
built_app="$derived_data/Build/Products/Release/LingoFloat.app"
staged_app="$staging/LingoFloat.app"

echo "==> Building LingoFloat $version (Release, arm64)"
env DEVELOPER_DIR="$xcode_dir" xcodebuild \
  -project "$project" \
  -scheme LingoFloat \
  -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath "$source_packages" \
  -derivedDataPath "$derived_data" \
  -quiet \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION=1 \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$built_app" ]]; then
  echo "ERROR: build succeeded without producing $built_app" >&2
  exit 1
fi

echo "==> Applying ad-hoc runtime signature"
codesign \
  --force \
  --deep \
  --sign - \
  --options runtime \
  --entitlements "$entitlements" \
  "$built_app"
codesign --verify --deep --strict --verbose=2 "$built_app"

bundle_version="$(defaults read "$built_app/Contents/Info" CFBundleShortVersionString)"
if [[ "$bundle_version" != "$version" ]]; then
  echo "ERROR: built app version is $bundle_version, expected $version" >&2
  exit 1
fi

echo "==> Packaging $dmg_name"
mkdir -p "$staging"
ditto "$built_app" "$staged_app"
ln -s /Applications "$staging/Applications"
cp "$project_root/Docs/dmg-readme.txt" "$staging/Read me first.txt"

hdiutil create \
  -volname "LingoFloat $version" \
  -srcfolder "$staging" \
  -format UDZO \
  -ov \
  "$dmg_path" >/dev/null
hdiutil verify "$dmg_path" >/dev/null

(
  cd "$build_dir"
  shasum -a 256 "$dmg_name" > "$(basename "$checksum_path")"
)

dmg_size="$(du -h "$dmg_path" | awk '{print $1}')"
dmg_sha="$(awk '{print $1}' "$checksum_path")"

echo
echo "==> Release artifacts ready"
echo "    DMG:    $dmg_path"
echo "    Size:   $dmg_size"
echo "    SHA256: $dmg_sha"
echo "    Note:   ad-hoc signed and not notarized"
