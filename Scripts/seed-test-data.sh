#!/usr/bin/env bash
# seed-test-data.sh
#
# Purpose: Populate the local Swift Data store with 7 days of synthetic
#          ActivityLog data. Useful for:
#            - Testing the history view without waiting a week
#            - Running LLM quality tests that require compliance history
#            - Developing the weekly coaching summary feature
#
# Usage:
#   ./Scripts/seed-test-data.sh                     # seed 7 days, ~70% compliance
#   ./Scripts/seed-test-data.sh --days 14           # seed 14 days
#   ./Scripts/seed-test-data.sh --compliance 30     # seed 7 days at 30% compliance (low)
#   ./Scripts/seed-test-data.sh --compliance 95     # seed 7 days at 95% compliance (high)
#   ./Scripts/seed-test-data.sh --clear             # clear all activity log entries
#
# When to run: during UI development, history view testing, and LLM quality testing.
#
# Requirements:
#   - HealthyMonitorSeeder CLI target (to be implemented in Week 2 alongside core models)
#   - App NOT running (to avoid Swift Data concurrency conflicts)

set -euo pipefail

DAYS="${2:-7}"
COMPLIANCE="${4:-70}"
CLEAR=false
[[ "${1:-}" == "--clear" ]] && CLEAR=true

BUILD_DIR="$(PWD)/.build"
SEEDER_BINARY="$BUILD_DIR/Release/HealthyMonitorSeeder"

log() { echo "[$(date +%H:%M:%S)] $*"; }

if $CLEAR; then
  log "Clearing ActivityLog data..."
  echo "  [STUB] Clear not yet implemented — delete the Swift Data store file manually:"
  echo "  ~/Library/Application Support/HealthyMonitor/default.store"
  exit 0
fi

log "Seeding $DAYS days of synthetic data at $COMPLIANCE% compliance..."

# TODO (Phase 1 Week 2): Implement HealthyMonitorSeeder Swift CLI target.
# It should:
#   1. Open the Swift Data store
#   2. Generate ActivityLog entries for the past N days
#      - 8 reminders/day (stand x4, water x3, stretch x1)
#      - Randomly mark COMPLIANCE% as .completed, rest as .missed or .skipped
#      - scheduledAt = day start + (idx * intervalMinutes)
#      - respondedAt = scheduledAt + random(30s...120s) for completed entries
#      - deviceSource = "mac"
#   3. Print a summary of entries created

echo ""
echo "  [STUB] Seeder not yet implemented."
echo "  Implement HealthyMonitorSeeder CLI target in Week 2."
echo ""
echo "  Seeder will generate:"
echo "    - $DAYS days × 8 reminders = $((DAYS * 8)) total ActivityLog entries"
echo "    - ~$((DAYS * 8 * COMPLIANCE / 100)) completed, rest missed/skipped"
echo "    - Types: stand (×4/day), water (×3/day), stretch (×1/day)"
echo ""

log "Done (stub)."
