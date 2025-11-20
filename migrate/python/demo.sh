#!/bin/bash
# Demonstrate migrating a Poetry-managed Python project into git-pkgs.
set -euo pipefail

PROJECT_URL="https://github.com/Textualize/rich.git"
PROJECT_TAG="v13.7.1"
SRC_DIR="poetry2pkgs-rich-src"
DST_DIR="poetry2pkgs-rich-pkgs"
PKG_NAME="rich-demo"
PKG_REV="HEAD"

echo "[demo] Cleaning old workspaces..."
rm -rf "$SRC_DIR" "$DST_DIR"

echo "[demo] Cloning $PROJECT_URL @$PROJECT_TAG ..."
git clone -q --depth 1 --branch "$PROJECT_TAG" "$PROJECT_URL" "$SRC_DIR"

echo "[demo] Migrating with poetry2pkgs..."
./poetry2pkgs.sh "$SRC_DIR" "$DST_DIR" "$PKG_NAME" "$PKG_REV"

echo "[demo] Dependency tree:"
git -C "$DST_DIR" pkgs tree
