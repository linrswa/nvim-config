#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
TARGET_DIR="$CONFIG_HOME/nvim"

for path in init.lua lua nvim-pack-lock.json; do
    if [[ ! -e "$SOURCE_DIR/$path" ]]; then
        printf 'Missing required source: %s\n' "$SOURCE_DIR/$path" >&2
        exit 1
    fi
done

mkdir -p "$CONFIG_HOME"
STAGING_DIR="$(mktemp -d "$CONFIG_HOME/.nvim-install.XXXXXX")"
cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp "$SOURCE_DIR/init.lua" "$STAGING_DIR/init.lua"
cp "$SOURCE_DIR/nvim-pack-lock.json" "$STAGING_DIR/nvim-pack-lock.json"
cp -R "$SOURCE_DIR/lua" "$STAGING_DIR/lua"

if [[ -L "$TARGET_DIR" ]] && [[ "$(cd "$TARGET_DIR" && pwd -P)" == "$SOURCE_DIR" ]]; then
    rm "$TARGET_DIR"
elif [[ -e "$TARGET_DIR" || -L "$TARGET_DIR" ]]; then
    BACKUP_DIR="$TARGET_DIR.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$TARGET_DIR" "$BACKUP_DIR"
    printf 'Existing config backed up to %s\n' "$BACKUP_DIR"
fi

mv "$STAGING_DIR" "$TARGET_DIR"
trap - EXIT

printf 'Installed Neovim config to %s\n' "$TARGET_DIR"
printf 'Included: init.lua, lua/, nvim-pack-lock.json\n'
printf 'Excluded: examples/, README.md, installer scripts, and Git metadata\n'
