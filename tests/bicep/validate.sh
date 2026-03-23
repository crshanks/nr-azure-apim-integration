#!/usr/bin/env bash
# tests/bicep/validate.sh
#
# Validates Bicep files without Azure credentials.
# Compiles Bicep → ARM JSON locally using either the standalone `bicep` binary
# or `az bicep build` (whichever is available). No subscription or login required.
#
# Usage:
#   ./tests/bicep/validate.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "==> Validating Bicep files"

# Resolve the build command — prefer standalone bicep binary, fall back to az bicep
if command -v bicep &>/dev/null; then
  build_cmd() { bicep build "$1" --outfile "$2" 2>&1; }
elif command -v az &>/dev/null; then
  build_cmd() { az bicep build --file "$1" --outfile "$2" 2>&1; }
else
  echo "    [ERROR] Neither 'bicep' nor 'az' found."
  echo "            Install the Bicep CLI: https://docs.microsoft.com/azure/azure-resource-manager/bicep/install"
  exit 1
fi

# ── Compile each main.bicep — warnings are fine, errors fail the check ────────
compile_bicep() {
  local label="$1"
  local file="$2"
  local out
  out="$(mktemp /tmp/bicep-arm-XXXX.json)"
  local output
  output=$(build_cmd "$file" "$out")
  local rc=$?
  rm -f "$out"
  if [[ $rc -ne 0 ]]; then
    echo "    [FAIL] $label"
    echo "$output"
    exit 1
  fi
  echo "    [PASS] $label"
}

compile_bicep "bicep/main.bicep"       "$REPO_ROOT/bicep/main.bicep"
compile_bicep "demo/bicep/main.bicep"  "$REPO_ROOT/demo/bicep/main.bicep"

echo "==> All Bicep files are valid"
