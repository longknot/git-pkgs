#!/bin/bash
# Demonstrate migrating a Go module with ~10-20 direct dependencies into git-pkgs.
# Uses gin as an example target.
set -euo pipefail

PROJECT="github.com/gin-gonic/gin"
REVISION="v1.11.0"
PKG_NAME="gin-demo"
PKG_REV="HEAD"

SRC_DIR="go2pkgs-gin-src"
DST_DIR="go2pkgs-gin-pkgs"

echo "[demo] Cleaning old workspaces..."
rm -rf "$SRC_DIR" "$DST_DIR"

echo "[demo] Cloning $PROJECT@$REVISION ..."
git clone -q --depth 1 --branch "$REVISION" "https://$PROJECT" "$SRC_DIR"

echo "[demo] Migrating with go2pkgs..."
./go2pkgs.sh "$SRC_DIR" "$DST_DIR" "$PKG_NAME" "$PKG_REV"

echo "[demo] Dependency tree:"
git -C "$DST_DIR" pkgs tree
