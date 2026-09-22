#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/build"
dist_dir="$project_dir/dist"
app_dir="$build_dir/CodexProcessCleaner.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"
archive_path="$dist_dir/CodexProcessCleaner-macOS-universal.zip"

mkdir -p "$macos_dir" "$resources_dir" "$dist_dir"

clang \
  -fobjc-arc \
  -O2 \
  -arch arm64 \
  -arch x86_64 \
  -mmacosx-version-min=14.0 \
  -framework Cocoa \
  "$project_dir/Sources/CodexProcessCleaner/main.m" \
  -o "$macos_dir/CodexProcessCleaner"

cp "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp "$project_dir/Resources/AppIcon.icns" "$resources_dir/AppIcon.icns"
chmod +x "$macos_dir/CodexProcessCleaner"
codesign --force --deep --sign - "$app_dir" >/dev/null
ditto -c -k --keepParent "$app_dir" "$archive_path"

codesign --verify --deep --strict "$app_dir"
lipo -info "$macos_dir/CodexProcessCleaner"
shasum -a 256 "$archive_path"
echo "$archive_path"
