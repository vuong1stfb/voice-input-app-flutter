#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="/root/projects/My-Project/input_app_flutter/"
TARGET_DIR="${1:-/mnt/c/dev/input_app_flutter/}"

mkdir -p "$TARGET_DIR"

rsync -a --delete \
  --exclude '.dart_tool' \
  --exclude 'build' \
  --exclude '.flutter-plugins' \
  --exclude '.flutter-plugins-dependencies' \
  --exclude '.packages' \
  "$SOURCE_DIR" \
  "$TARGET_DIR"

printf 'Synced input_app_flutter to: %s\n' "$TARGET_DIR"
