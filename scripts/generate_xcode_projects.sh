#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
xcodegen generate -s ConfigMac/project.yml
xcodegen generate -s "sources App/Config/project.yml"

echo "Generated macOS and iOS Xcode projects."
