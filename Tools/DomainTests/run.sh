#!/bin/zsh
# Compiles the Domain layer (plus the in-memory store) with the checks in main.swift and runs them on macOS.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${TMPDIR:-/tmp}/cuepilot-domain-tests"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
xcrun swiftc -O -o "$OUT" \
  "$ROOT"/CuePilot/Domain/**/*.swift \
  "$ROOT"/CuePilot/Data/Persistence/FileDatabaseStore.swift \
  "$ROOT"/Tools/DomainTests/main.swift
"$OUT"
