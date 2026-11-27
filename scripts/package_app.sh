#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
app_bundle="$project_dir/dist/DayNote.app"
macos_dir="$app_bundle/Contents/MacOS"
resources_dir="$app_bundle/Contents/Resources"

cd "$project_dir"
if [[ -z "${SDKROOT:-}" && ! -d /Applications/Xcode.app && -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]]; then
    SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build -c release --build-system native
else
    swift build -c release
fi

mkdir -p "$macos_dir" "$resources_dir"
install -m 755 "$project_dir/.build/release/DayNote" "$macos_dir/DayNote"
install -m 644 "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
if [[ -f "$project_dir/Resources/AppIcon.icns" ]]; then
    install -m 644 "$project_dir/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"
fi

codesign --force --deep --sign - "$app_bundle"
touch "$app_bundle"

echo "$app_bundle"
