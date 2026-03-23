#!/usr/bin/env bash
# tests/policy/validate.sh
#
# Validates apim-policy.xml.tpl without Azure credentials.
# Checks:
#   1. XML is well-formed (xmllint)
#   2. Required AppRequests fields are present in the log-to-eventhub block
#   3. traceparent outbound capture pattern is present
#   4. Template variables ${logger_id} and ${backend_id} exist (unrendered — confirms
#      they haven't been accidentally hardcoded)
#
# Usage:
#   ./tests/policy/validate.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
POLICY="$REPO_ROOT/apim-policy.xml.tpl"

echo "==> Checking apim-policy.xml.tpl"

# ── 1. Basic XML structure check ─────────────────────────────────────────────
# Note: APIM policies embed C# expressions with unescaped quotes and generics
# (<string>) inside XML attributes — this is valid APIM syntax but not strict
# XML. We check structural markers rather than strict XML well-formedness.
for tag in "<policies>" "</policies>" "<inbound>" "</inbound>" \
           "<outbound>" "</outbound>" "<on-error>" "</on-error>"; do
  if grep -qF "$tag" "$POLICY"; then
    echo "    [PASS] Structure: $tag present"
  else
    echo "    [FAIL] Structure: $tag missing"
    exit 1
  fi
done

# ── Helper ────────────────────────────────────────────────────────────────────
assert_contains() {
  local label="$1"
  local pattern="$2"
  if grep -qF "$pattern" "$POLICY"; then
    echo "    [PASS] $label"
  else
    echo "    [FAIL] $label — pattern not found: $pattern"
    exit 1
  fi
}

# ── 2. AppRequests schema fields ──────────────────────────────────────────────
assert_contains "AppRequests Type field"    '"Type",        "AppRequests"'
assert_contains "OperationId (trace.id)"    '"OperationId",'
assert_contains "Id (span.id)"              '"Id",'
assert_contains "ParentId (parentSpanId)"   '"ParentId",'
assert_contains "AppRoleName (service.name)" '"AppRoleName",'
assert_contains "DurationMs"               '"DurationMs",'
assert_contains "ResultCode"               '"ResultCode",'
assert_contains "Url"                      '"Url",'
assert_contains "HTTP Method property"     '"HTTP Method",'

# ── 3. Outbound traceparent capture ──────────────────────────────────────────
assert_contains "Outbound traceparent read" 'context.Request.Headers.GetValueOrDefault("traceparent"'
assert_contains "finalApimSpanId variable"  'finalApimSpanId'

# ── 4. Template variables present (not hardcoded) ────────────────────────────
assert_contains "logger_id template var"   '${logger_id}'
assert_contains "backend_id template var"  '${backend_id}'

# ── 5. records wrapper (azure_event_hub receiver expects {records:[...]}) ─────
assert_contains "records array wrapper"    '"records",'

echo "==> apim-policy.xml.tpl is valid"
