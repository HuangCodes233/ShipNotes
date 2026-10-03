#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

xcrun swift-format lint --strict --recursive Package.swift Sources Tests
swift test
git diff --check
