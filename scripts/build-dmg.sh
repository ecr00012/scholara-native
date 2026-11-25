#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

scripts/build-app.sh
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)"
architecture="$(lipo -archs build/Scholara.app/Contents/MacOS/Scholara | tr ' ' '-')"
filename="Scholara-${version}-${architecture}.dmg"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/ScholaraDMG.XXXXXX")"
mount_path=""
cleanup() {
    if [ -n "$mount_path" ]; then hdiutil detach "$mount_path" >/dev/null 2>&1 || true; fi
    rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$staging_dir/Install"
# Extract the verified archive rather than copying a cloud-managed app bundle.
ditto -x -k build/Scholara-macOS.zip "$staging_dir/Install"
ln -s /Applications "$staging_dir/Install/Applications"
cat > "$staging_dir/Install/Read Me.txt" <<'EOF'
Scholara for macOS

Drag Scholara.app to Applications, then eject this disk image.
Requires macOS 14 or later. This image is built for the architecture in its filename.

This preview is ad-hoc signed, not Developer ID signed or notarized.
macOS Gatekeeper may prevent it from opening as a trusted downloaded application.

Paper and Soft: Settings > Reading.
Scroll / Pages: reader toolbar.
OpenRouter model paths: Settings > AI & Models.
Embedding is optional and enabled explicitly for each book.

The native library is separate from the original Tauri library:
~/Library/Application Support/ScholaraNative/
Use Settings > Library & Data to import an old library explicitly.

Source, compatibility notes, and validation:
https://github.com/ecr00012/scholara-native
EOF
codesign --verify --deep --strict "$staging_dir/Install/Scholara.app"
hdiutil create -volname "Scholara" -srcfolder "$staging_dir/Install" -fs HFS+ -format UDZO "$staging_dir/$filename"
hdiutil verify "$staging_dir/$filename"

mount_path="$staging_dir/Mounted"
mkdir -p "$mount_path"
hdiutil attach "$staging_dir/$filename" -readonly -nobrowse -mountpoint "$mount_path"
codesign --verify --deep --strict "$mount_path/Scholara.app"
cmp "$mount_path/Scholara.app/Contents/MacOS/Scholara" "$staging_dir/Install/Scholara.app/Contents/MacOS/Scholara"
test "$(readlink "$mount_path/Applications")" = /Applications
test -s "$mount_path/Read Me.txt"
hdiutil detach "$mount_path"
mount_path=""

mv "$staging_dir/$filename" "build/$filename"
(cd build && shasum -a 256 "$filename" > "$filename.sha256")
printf '%s\n' "$PWD/build/$filename" "$PWD/build/$filename.sha256"
