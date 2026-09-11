#!/bin/zsh
set -euo pipefail

project_root="${0:A:h:h}"
xcode_dir="${LINGOFLOAT_XCODE_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
local_config="$project_root/LingoFloat/Local.xcconfig"

if [[ ! -f "$local_config" ]]; then
  cp "$project_root/LingoFloat/Local.xcconfig.template" "$local_config"
fi

cd "$project_root"
env DEVELOPER_DIR="$xcode_dir" xcodebuild \
  -project LingoFloat/LingoFloat.xcodeproj \
  -scheme LingoFloat \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -clonedSourcePackagesDirPath .build/SourcePackages \
  -derivedDataPath .build/DerivedData \
  -quiet \
  CODE_SIGNING_ALLOWED=NO \
  test
