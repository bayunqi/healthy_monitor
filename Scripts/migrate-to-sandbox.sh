#!/usr/bin/env bash
#
# migrate-to-sandbox.sh
# One-time migration: copies v1 data from the unsandboxed location into the
# sandbox container so v1.1 (which is sandboxed) can read it on first launch.
#
# Run this AFTER installing v1.1 and BEFORE launching it for the first time
# (or at least before starting your first focus session in v1.1).

set -euo pipefail

LEGACY_DIR="$HOME/Library/Application Support/HealthyMonitor"
SANDBOX_DIR="$HOME/Library/Containers/com.healthymonitor.mac/Data/Library/Application Support/HealthyMonitor"

if [[ ! -d "$LEGACY_DIR" ]]; then
  echo "✓ No legacy data found at $LEGACY_DIR — nothing to migrate."
  exit 0
fi

if [[ ! -d "$(dirname "$SANDBOX_DIR")" ]]; then
  echo "✗ Sandbox container does not exist yet."
  echo "  Launch v1.1 once (just open the app) so macOS creates the container,"
  echo "  then re-run this script."
  exit 1
fi

if [[ -d "$SANDBOX_DIR" ]] && [[ -n "$(ls -A "$SANDBOX_DIR" 2>/dev/null)" ]]; then
  echo "⚠ Sandbox container already has data at $SANDBOX_DIR"
  read -r -p "Overwrite with legacy data? [y/N] " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo "Aborted. No changes made."
    exit 0
  fi
fi

mkdir -p "$SANDBOX_DIR"
cp -R "$LEGACY_DIR/." "$SANDBOX_DIR/"
echo "✓ Migrated:"
echo "  from: $LEGACY_DIR"
echo "  to:   $SANDBOX_DIR"
echo ""
echo "Files in sandbox container:"
ls -la "$SANDBOX_DIR"
