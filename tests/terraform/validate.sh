#!/usr/bin/env bash
# tests/terraform/validate.sh
#
# Validates the Terraform configuration without Azure credentials.
# Runs entirely locally — no cloud access required.
#
# Checks:
#   1. terraform init (plugin download)
#   2. terraform validate (syntax + type checking)
#   3. tflint (lint rules) — skipped if not installed
#
# Usage:
#   ./tests/terraform/validate.sh [terraform-dir]
#   ./tests/terraform/validate.sh terraform        # default
#   ./tests/terraform/validate.sh demo/terraform

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TF_DIR="${1:-terraform}"
TARGET="$REPO_ROOT/$TF_DIR"

echo "==> Validating Terraform in ${TF_DIR}/"

if ! command -v terraform &>/dev/null; then
  echo "    [ERROR] terraform not found — install from https://developer.hashicorp.com/terraform/downloads"
  exit 1
fi

# ── 1. terraform init ─────────────────────────────────────────────────────────
echo "    Running terraform init..."
terraform -chdir="$TARGET" init -backend=false -input=false -no-color \
  > /dev/null 2>&1
echo "    [PASS] terraform init"

# ── 2. terraform validate ─────────────────────────────────────────────────────
terraform -chdir="$TARGET" validate -no-color
echo "    [PASS] terraform validate"

# ── 3. tflint ─────────────────────────────────────────────────────────────────
if command -v tflint &>/dev/null; then
  tflint --chdir="$TARGET" --no-color
  echo "    [PASS] tflint"
else
  echo "    [SKIP] tflint not found — install from https://github.com/terraform-linters/tflint"
fi

echo "==> ${TF_DIR}/ Terraform is valid"
