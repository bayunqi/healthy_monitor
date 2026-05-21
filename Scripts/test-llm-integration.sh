#!/usr/bin/env bash
# test-llm-integration.sh
#
# Purpose: Run the LLM quality test suite against the live Claude API.
#          Tests cover onboarding extraction accuracy, coaching tone,
#          adaptive interval tool use, and weekly insight quality.
#
# IMPORTANT: This script costs real Anthropic API tokens.
#            Run weekly (Sunday) — NOT per-PR. Per-PR tests use mocked responses.
#
# Usage:
#   ./Scripts/test-llm-integration.sh               # run quality tests, print results
#   ./Scripts/test-llm-integration.sh --weekly-report  # also append row to PROGRESS.md
#
# Requirements:
#   - ANTHROPIC_API_KEY set in environment
#   - xcodebuild available (Xcode 16+)

set -euo pipefail

WEEKLY_REPORT=false
[[ "${1:-}" == "--weekly-report" ]] && WEEKLY_REPORT=true

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "Error: ANTHROPIC_API_KEY is not set."
  echo "  Export it before running: export ANTHROPIC_API_KEY=sk-ant-..."
  exit 1
fi

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "Running LLM quality tests against claude-sonnet-4-6..."
log "(This will consume API tokens — weekly use only)"

# TODO (Phase 1 Week 5): Implement once LLMService is complete.
# Run: xcodebuild test -scheme HealthyMonitorCoreTests -testPlan LLMQualityTests
#
# Test plan covers:
#   - LLMServiceTests/testOnboardingExtractsPainPointsCorrectly
#   - LLMServiceTests/testCoachDoesNotGuiltTripMissedReminders
#   - LLMServiceTests/testAdaptiveIntervalDecreaseForLowCompliance
#   - LLMServiceTests/testWeeklyInsightContainsSpecificData
#
# After tests, parse xcresult and compute:
#   EXTRACTION_ACCURACY = passed extraction assertions / total
#   TOOL_USE_SUCCESS    = test cases where tool was called / total cases expecting tool call
#   COACHING_RELEVANCE  = manual score (prompted for after test run)

echo ""
echo "  [STUB] LLM quality tests not yet implemented."
echo "  Implement once LLMService is complete (Week 5)."
echo ""
echo "  Tests to implement:"
echo "    testOnboardingExtractsPainPointsCorrectly()"
echo "    testCoachDoesNotGuiltTripMissedReminders()"
echo "    testAdaptiveIntervalDecreaseForLowCompliance()"
echo "    testWeeklyInsightContainsSpecificData()"
echo ""

if $WEEKLY_REPORT; then
  DATE=$(date +%Y-%m-%d)
  echo "  [STUB] Would append to PROGRESS.md: | $DATE | — | — | — | stub run |"
fi

log "Done."
