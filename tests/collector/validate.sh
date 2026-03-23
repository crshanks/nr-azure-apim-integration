#!/usr/bin/env bash
# tests/collector/validate.sh
#
# Validates otel-collector-config.yaml using the otelcol-contrib Docker image.
# Runs entirely locally — no Azure credentials required.
#
# Usage:
#   ./tests/collector/validate.sh
#   ./tests/collector/validate.sh 0.148.0   # optional version override

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONFIG="$REPO_ROOT/otel-collector-config.yaml"

# Extract the image version from variables.tf unless overridden
if [[ $# -ge 1 ]]; then
  VERSION="$1"
else
  VERSION=$(grep -A5 'otel_collector_image' "$REPO_ROOT/terraform/variables.tf" \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1)
fi

IMAGE="otel/opentelemetry-collector-contrib:${VERSION}"

echo "==> Validating otel-collector-config.yaml with ${IMAGE}"

# Substitute env var placeholders with dummy values so the validator
# doesn't reject them as missing — we're testing structure, not secrets.
PATCHED=$(sed \
  -e 's|\${env:AZURE_EVENTHUB_CONNECTION}|Endpoint=sb://test.servicebus.windows.net/;SharedAccessKeyName=k;SharedAccessKey=dGVzdA==;EntityPath=test|g' \
  -e 's|\${env:NEW_RELIC_LICENSE_KEY}|aaaabbbbccccddddeeeeffffaaaabbbbccccdddd|g' \
  "$CONFIG")

TMPFILE=$(mktemp)
echo "$PATCHED" > "$TMPFILE"

docker run --rm \
  -v "$TMPFILE:/otel-config.yaml:ro" \
  --entrypoint /otelcol-contrib \
  "$IMAGE" \
  validate --config "file:/otel-config.yaml"

rm -f "$TMPFILE"

echo "==> otel-collector-config.yaml is valid"
