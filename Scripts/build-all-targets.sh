#!/usr/bin/env bash
# build-all-targets.sh
#
# Purpose: Build all platform targets (macOS, iOS, watchOS) and report
#          compilation errors. Use before committing or as a quick sanity check.
#
# Usage:
#   ./Scripts/build-all-targets.sh           # build all available targets
#   ./Scripts/build-all-targets.sh --mac     # macOS only
#   ./Scripts/build-all-targets.sh --ios     # iOS only
#   ./Scripts/build-all-targets.sh --watch   # watchOS only
#
# When to run: before any commit; after dependency or project config changes.
#
# Requirements: Xcode 16+, macOS 15+

set -euo pipefail

TARGET="${1:-all}"
PASS=0
FAIL=0
BUILD_DIR="$(PWD)/.build"

log()  { echo "[$(date +%H:%M:%S)] $*"; }
ok()   { echo "  ✓ $1"; ((PASS++)); }
err()  { echo "  ✗ $1"; echo "    $2"; ((FAIL++)); }

build() {
  local name="$1"
  local scheme="$2"
  local dest="$3"
  log "Building $name ($scheme)..."
  if xcodebuild -scheme "$scheme" \
      -configuration Debug \
      -derivedDataPath "$BUILD_DIR" \
      -destination "$dest" \
      build 2>&1 | tail -3; then
    ok "$name"
  else
    err "$name" "Build failed — run without tail to see full output"
  fi
}

echo ""
echo "HealthyMonitor — Build All Targets"
echo "==================================="

# Phase 1 targets (implemented)
if [[ "$TARGET" == "all" || "$TARGET" == "--mac" ]]; then
  build "macOS menu bar" "HealthyMonitorMac" "platform=macOS"
fi

# Phase 2 targets (stubs — will fail until implemented)
if [[ "$TARGET" == "all" || "$TARGET" == "--ios" ]]; then
  log "iOS target — skipping (Phase 2, not yet implemented)"
  echo "  [skipped] HealthyMonitor (iOS) — implement in Phase 2"
fi

if [[ "$TARGET" == "all" || "$TARGET" == "--watch" ]]; then
  log "watchOS target — skipping (Phase 2, not yet implemented)"
  echo "  [skipped] HealthyMonitorWatch (watchOS) — implement in Phase 2"
fi

# HealthyMonitorCore unit tests
if [[ "$TARGET" == "all" ]]; then
  log "Running HealthyMonitorCore unit tests..."
  if xcodebuild test -scheme "HealthyMonitorCoreTests" \
      -derivedDataPath "$BUILD_DIR" \
      -destination "platform=macOS" 2>&1 | tail -3; then
    ok "HealthyMonitorCore tests"
  else
    err "HealthyMonitorCore tests" "Tests failed"
  fi
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
echo ""
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
