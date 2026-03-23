/**
 * tracing.js — OTel SDK bootstrap for the mock backend.
 *
 * Must be required BEFORE any other module (via --require flag or first import).
 * Reads the traceparent header forwarded by APIM and uses it as the parent
 * context for all spans emitted by this process.
 *
 * Environment variables:
 *   NEW_RELIC_LICENSE_KEY  : 40-char New Relic ingest key
 *   OTEL_SERVICE_NAME      : Service name shown in NR Service Map (default: mock-backend)
 *   OTEL_EXPORTER_OTLP_ENDPOINT : OTLP endpoint (default: https://otlp.nr-data.net:4318)
 */

"use strict";

const { NodeSDK } = require("@opentelemetry/sdk-node");
const { OTLPTraceExporter } = require("@opentelemetry/exporter-trace-otlp-proto");
const { Resource } = require("@opentelemetry/resources");
const { SemanticResourceAttributes } = require("@opentelemetry/semantic-conventions");
const { getNodeAutoInstrumentations } = require("@opentelemetry/auto-instrumentations-node");

const serviceName = process.env.OTEL_SERVICE_NAME || "mock-backend";
const endpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT || "https://otlp.nr-data.net:4318";
const licenseKey = process.env.NEW_RELIC_LICENSE_KEY;

if (!licenseKey) {
  console.warn("[tracing] WARNING: NEW_RELIC_LICENSE_KEY not set — traces will not reach New Relic");
}

const exporter = new OTLPTraceExporter({
  url: `${endpoint}/v1/traces`,
  headers: {
    "api-key": licenseKey || "",
  },
});

const sdk = new NodeSDK({
  resource: new Resource({
    [SemanticResourceAttributes.SERVICE_NAME]: serviceName,
    [SemanticResourceAttributes.SERVICE_VERSION]: "1.0.0",
    "cloud.provider": "local",
    "demo.component": "mock-backend",
  }),
  traceExporter: exporter,
  instrumentations: [
    getNodeAutoInstrumentations({
      // Disable noisy instrumentations for the demo
      "@opentelemetry/instrumentation-fs": { enabled: false },
      "@opentelemetry/instrumentation-dns": { enabled: false },
      "@opentelemetry/instrumentation-net": { enabled: false },
    }),
  ],
});

sdk.start();
console.log(`[tracing] OTel SDK started — service=${serviceName} endpoint=${endpoint}`);

process.on("SIGTERM", () => {
  sdk.shutdown().then(() => process.exit(0));
});
