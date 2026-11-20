#!/usr/bin/env bash
# Installs the Herdr app mods in scripts/herdr-app-mods.txt. The mod code is
# not in this repository: each mod comes from its own installer, at the
# pinned tag, then its local patches in scripts/patches/ are applied.
# Run it with the Herdr app open, after you stow herdr-app. Run it again to
# upgrade, after you change a tag (and make its patches again).
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/herdr-app-mods.txt"
PATCHES="$HERE/patches"
HOME_DIR="${HERDR_APP_HOME:-$HOME/.config/herdr-app}"

die() { echo "herdr-app-mods: $*" >&2; exit 1; }

# Check every patch file before anything is installed.
while read -r repo tag patches <&3; do
  case "$repo" in "" | "#"*) continue ;; esac
  [ -n "$tag" ] || die "$repo: no tag"
  for p in $patches; do
    [ -f "$PATCHES/$p" ] || die "$repo: no patch file $PATCHES/$p"
  done
done 3<"$LIST"

apply_patch() {
  local repo=$1 tag=$2 file="$PATCHES/$3"
  if patch -d "$HOME_DIR/mods" -p1 -R --dry-run --force --silent <"$file" >/dev/null 2>&1; then
    echo "$3: already applied"
  elif patch -d "$HOME_DIR/mods" -p1 --dry-run --forward --silent <"$file" >/dev/null 2>&1; then
    patch -d "$HOME_DIR/mods" -p1 --forward --no-backup-if-mismatch <"$file"
  else
    die "$3 does not apply to $repo $tag: make the patch again against $tag"
  fi
}

while read -r repo tag patches <&3; do
  case "$repo" in "" | "#"*) continue ;; esac
  echo "== $repo $tag"
  installer=$(mktemp)
  curl -fsSL "https://raw.githubusercontent.com/$repo/$tag/install.sh" -o "$installer" ||
    die "$repo: no install.sh at $tag"
  grep -q -- "--app" "$installer" || die "$repo: its install.sh has no --app option"
  sh "$installer" --app --version "$tag"
  rm -f "$installer"
  for p in $patches; do apply_patch "$repo" "$tag" "$p"; done
done 3<"$LIST"

# The installers add keys only where they are free and edit a layout only
# when it does not have their mod yet: with this repository's files, they
# write neither, so the stow symlinks stay.
for link in keys.json settings.json layouts/custom.json; do
  [ -L "$HOME_DIR/$link" ] || echo "warning: $HOME_DIR/$link is not a symlink any more; stow herdr-app again" >&2
done
