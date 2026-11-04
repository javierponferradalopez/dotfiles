#!/usr/bin/env bash
# Installs each Herdr plugin in herdr-plugins.txt that is not installed yet.
set -euo pipefail

list="$(dirname "$0")/herdr-plugins.txt"
installed="$(herdr plugin list 2>/dev/null || true)"

{ grep -vE '^\s*(#|$)' "$list" || true; } | while read -r repo; do
  echo -e "\nInstalling Herdr plugin $repo"
  if grep -q "github:$repo@" <<<"$installed"; then
    echo "$repo is already installed"
  else
    herdr plugin install "$repo" --yes && echo "$repo installed"
  fi
done

echo -e "\nHerdr starts new plugins when its server starts."
echo "If the server is running now, run 'herdr server stop' or invoke the plugin restart action."
