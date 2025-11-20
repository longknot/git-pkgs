#!/bin/bash
# Demonstrate migrating a Rust project (ripgrep) into a git-pkgs workspace.
set -euo pipefail

PROJECT_URL="https://github.com/BurntSushi/ripgrep.git"
PROJECT_TAG="14.1.0"

SRC_DIR="cargo2pkgs-ripgrep-src"
DST_DIR="cargo2pkgs-ripgrep-pkgs"

PKG_NAME="ripgrep-demo"
PKG_REV="HEAD"

echo "[demo] Cleaning old workspaces..."
rm -rf "$SRC_DIR" "$DST_DIR"

echo "[demo] Cloning ripgrep @$PROJECT_TAG ..."
git clone --depth 1 --branch "$PROJECT_TAG" "$PROJECT_URL" "$SRC_DIR"

echo "[demo] Migrating with cargo2pkgs..."
./cargo2pkgs.sh "$SRC_DIR" "$DST_DIR" "$PKG_NAME" "$PKG_REV"

echo "[demo] Dependency tree:"
git -C "$DST_DIR" pkgs tree
