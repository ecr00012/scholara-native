#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration" --product Scholara
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
# Sign outside iCloud/File Provider folders, which can add Finder metadata mid-sign.
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/ScholaraPackage.XXXXXX")"
trap 'rm -rf "$staging_dir"' EXIT
app_path="$staging_dir/Scholara.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/Scholara" "$app_path/Contents/MacOS/Scholara"
cp Packaging/Info.plist "$app_path/Contents/Info.plist"
cp Packaging/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
cp LICENSE "$app_path/Contents/Resources/LICENSE"
rm -f "$app_path/Contents/Resources/ZIPFoundation-LICENSE"
cp .build/checkouts/ZIPFoundation/LICENSE "$app_path/Contents/Resources/ZIPFoundation-LICENSE"
# ZIPFoundation has only a privacy manifest resource; it performs no runtime resource lookup.
# Keep it in the standard signed Resources location, not the bundle root.
for resource in "$bin_dir"/ZIPFoundation_ZIPFoundation.bundle; do
    if [ -d "$resource" ]; then
        rm -rf "$app_path/$(basename "$resource")"
        rm -rf "$app_path/Contents/Resources/$(basename "$resource")"
        cp -R "$resource" "$app_path/Contents/Resources/"
    fi
done
/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app_path/Contents/Info.plist" >/dev/null
cp Packaging/Lucide-LICENSE "$app_path/Contents/Resources/Lucide-LICENSE"
chmod -R u+w "$app_path"
xattr -cr "$app_path"
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" "$app_path"
codesign --verify --deep --strict "$app_path"
mkdir -p "$PWD/build"
output_app="$PWD/build/Scholara.app"
rm -rf "$output_app"
ditto --norsrc --noextattr "$app_path" "$output_app"
ditto -c -k --norsrc --noextattr --keepParent "$app_path" "$PWD/build/Scholara-macOS.zip"
printf '%s\n' "$output_app" "$PWD/build/Scholara-macOS.zip"
