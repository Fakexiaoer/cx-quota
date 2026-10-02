#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
source_app="$repo_dir/build/CX Quota.app"
target_dir="${HOME:?}/Applications"
target_app="$target_dir/CX Quota.app"
replace=false

usage() {
  print 'Usage: ./scripts/install-app.sh --apply [--replace]'
  print 'Copies build/CX Quota.app to ~/Applications.'
  print '--replace moves an existing app aside before installing.'
}

[[ "${1:-}" == "--apply" && ( $# -eq 1 || ( $# -eq 2 && "${2:-}" == "--replace" ) ) ]] || {
  usage
  exit 1
}
[[ "${2:-}" != "--replace" ]] || replace=true

[[ -d "$source_app" ]] || {
  print -u2 "build the app first: ./scripts/build-app.sh"
  exit 1
}
if [[ -e "$target_app" ]]; then
  [[ "$replace" == true ]] || {
    print -u2 "refusing to replace existing app: $target_app"
    exit 1
  }
  backup_app="${target_app}.backup-$(date +%Y%m%d%H%M%S)"
  mv "$target_app" "$backup_app"
  print "backup: $backup_app"
fi

mkdir -p "$target_dir"
ditto "$source_app" "$target_app"
print "installed: $target_app"
