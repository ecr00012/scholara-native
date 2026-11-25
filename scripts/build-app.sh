#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration" --product Scholara
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/build/Scholara.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/Scholara" "$app_path/Contents/MacOS/Scholara"
cp Packaging/Info.plist "$app_path/Contents/Info.plist"
cp Packaging/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
cp LICENSE "$app_path/Contents/Resources/LICENSE"
cp .build/checkouts/ZIPFoundation/LICENSE "$app_path/Contents/Resources/ZIPFoundation-LICENSE"
# ZIPFoundation has only a privacy manifest resource; it performs no runtime resource lookup.
# Keep it in the standard signed Resources location, not the bundle root.
for resource in "$bin_dir"/*.bundle; do
    if [ -d "$resource" ]; then
        rm -rf "$app_path/$(basename "$resource")"
        rm -rf "$app_path/Contents/Resources/$(basename "$resource")"
        cp -R "$resource" "$app_path/Contents/Resources/"
    fi
done
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist" >/dev/null
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf '%s\n' "$app_path"
