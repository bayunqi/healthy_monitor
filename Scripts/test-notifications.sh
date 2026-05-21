#!/usr/bin/env bash
# test-notifications.sh
#
# Purpose: Verify the full reminder → notification → log cycle works.
# Schedules a test notification 5 seconds in the future, waits for delivery,
# then checks that an ActivityLog entry was created with the correct response.
#
# Usage:
#   ./Scripts/test-notifications.sh              # test all reminder types
#   ./Scripts/test-notifications.sh --type stand # test a single type
#   ./Scripts/test-notifications.sh --type water
#   ./Scripts/test-notifications.sh --type stretch
#
# When to run: after any change to ReminderEngine, NotificationService, or ActivityLogger.
#
# Requirements:
#   - macOS app built in Debug configuration
#   - Notification permissions granted
#   - App running (or launched by this script)

set -euo pipefail

SCHEME="HealthyMonitorMac"
BUILD_DIR="$(PWD)/.build"
TYPE="${2:-all}"
PASS=0
FAIL=0

log() { echo "[$(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; ((PASS++)); }
fail() { echo "  ✗ $*"; ((FAIL++)); }

log "Building $SCHEME in Debug..."
xcodebuild -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  -destination "platform=macOS" \
  build 2>&1 | tail -5

log "Running notification delivery test (type: $TYPE)..."

# TODO (Phase 1 Week 3): Replace stub below with actual test runner
# that calls the HealthyMonitorSeeder CLI tool to inject a test reminder
# with a 5-second trigger, then polls ActivityLog for the expected entry.

echo ""
echo "  [STUB] Notification test not yet implemented."
echo "  Implement once ReminderEngine + ActivityLogger are complete (Week 3)."
echo ""
echo "  Expected test flow:"
echo "    1. Inject reminder via HealthyMonitorSeeder --test-notification --delay 5"
echo "    2. Wait 10 seconds"
echo "    3. Assert ActivityLog contains entry with scheduledAt ~now, response != nil"
echo "    4. Assert next reminder is scheduled in lastFiredAt + intervalMinutes"
echo ""

log "Summary: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
