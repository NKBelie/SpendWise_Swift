#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
name="${1:-spendwise}"
if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
  echo 'Use a screenshot name containing letters, numbers, underscores or hyphens.' >&2
  exit 1
fi
mkdir -p screenshots
xcrun simctl io booted screenshot "screenshots/${name}.png"
