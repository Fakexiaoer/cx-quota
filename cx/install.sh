#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SOURCE="$REPOSITORY_ROOT/cx/bin/cx"
readonly TARGET_DIRECTORY="${HOME:?HOME must be set}/.local/bin"
readonly TARGET="$TARGET_DIRECTORY/cx"

die() {
  printf 'cx install: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ./cx/install.sh [--force]

Creates ~/.local/bin/cx as a symbolic link to this checkout.
Keep the checkout in place; pulling updates updates the command automatically.
Use --force to move an existing cx command aside before installing.
EOF
}

[[ $# -le 1 ]] || { usage >&2; exit 1; }
force=false
case "${1:-}" in
  '') ;;
  --force) force=true ;;
  *) usage >&2; exit 1 ;;
esac

[[ -x "$SOURCE" ]] || die "launcher is missing or not executable: $SOURCE"
mkdir -p "$TARGET_DIRECTORY"

if [[ -L "$TARGET" && "$(readlink "$TARGET")" == "$SOURCE" ]]; then
  printf 'cx is already installed: %s -> %s\n' "$TARGET" "$SOURCE"
  exit 0
fi

if [[ -e "$TARGET" || -L "$TARGET" ]]; then
  [[ "$force" == true ]] || die "existing command found at $TARGET; rerun with --force"
  backup="$TARGET.cx-backup-$(date +%Y%m%d%H%M%S)"
  mv "$TARGET" "$backup"
  printf 'backup: %s\n' "$backup"
fi

ln -s "$SOURCE" "$TARGET"
printf 'installed: %s -> %s\n' "$TARGET" "$SOURCE"
