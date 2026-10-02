#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
output_dir="$repo_dir/build"
app_dir="$output_dir/CX Quota.app"
replace=false

usage() {
  print 'Usage: ./scripts/build-app.sh [--replace]'
  print 'Builds CX Quota.app. --replace moves an existing build aside first.'
}

if (( $# > 1 )) || [[ "${1:-}" != "" && "${1:-}" != "--replace" ]]; then
  usage
  exit 1
fi
[[ "${1:-}" != "--replace" ]] || replace=true

if [[ -e "$app_dir" ]]; then
  [[ "$replace" == true ]] || {
    print -u2 "build output already exists: $app_dir"
    print -u2 "use --replace to move it aside before rebuilding"
    exit 1
  }
  backup_app="${app_dir}.backup-$(date +%Y%m%d%H%M%S)"
  mv "$app_dir" "$backup_app"
  print "backup: $backup_app"
fi

swift build --package-path "$repo_dir" -c release
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$repo_dir/.build/release/CXQuota" "$app_dir/Contents/MacOS/CXQuota"
cp "$repo_dir/app/Info.plist" "$app_dir/Contents/Info.plist"
cp "$repo_dir/app/CXQuota.icns" "$app_dir/Contents/Resources/CXQuota.icns"
codesign --force --deep --sign - "$app_dir"
print "created: $app_dir"
