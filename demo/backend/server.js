/**
 * server.js — Mock Backend BFF
 *
 * This service demonstrates the backend leg of the distributed trace.
 * When APIM forwards a request, it includes an updated traceparent header
 * where APIM's span ID is the parent. This service:
 *
 * 1. Reads the traceparent header (auto-propagated by OTel HTTP instrumentation)
 * 2. Emits a child span under that parent, completing the 3-hop trace:
 *    Browser → APIM → Backend
 * 3. Returns the trace context in the response body for easy verification
 *
 * The OTel auto-instrumentations handle W3C context propagation automatically —
 * any span created during the request handler is automatically parented to the
 * incoming traceparent. No manual context extraction is needed.
 */

"use strict";

// Bootstrap OTel BEFORE requiring express or any other instrumented lib
require("./tracing");

const express = require("express");
const { trace, context, SpanStatusCode } = require("@opentelemetry/api");

const app = express();
const PORT = process.env.PORT || 3001;

app.use(express.json());

// CORS — allow the mock client to call this service
app.use((req, res, next) => {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Headers", "traceparent,tracestate,content-type");
  next();
});

/**
 * GET /api/data
 *
 * Primary demo endpoint. APIM routes requests here.
 * Emits a child span with attributes that will appear in New Relic.
 */
app.get("/api/data", (req, res) => {
  const tracer = trace.getTracer("mock-backend");
  const incomingTraceparent = req.headers["traceparent"] || "not-present";

  // The OTel HTTP instrumentation has already extracted the traceparent and
  // set it as the active context. Any span we create here is automatically
  // parented under APIM's span ID.
  const span = tracer.startSpan("backend.processRequest", {
    attributes: {
      "http.method": req.method,
      "http.url": req.url,
      "http.route": "/api/data",
      "backend.source": "mock-backend",
      "incoming.traceparent": incomingTraceparent,
    },
  });

  // Simulate some processing work
  const activeSpan = trace.getActiveSpan();
  const spanContext = activeSpan ? activeSpan.spanContext() : span.spanContext();

  const responseBody = {
    message: "Hello from mock-backend!",
    traceContext: {
      traceId: spanContext.traceId,
      spanId: spanContext.spanId,
      traceparentReceived: incomingTraceparent,
    },
    timestamp: new Date().toISOString(),
  };

  span.setStatus({ code: SpanStatusCode.OK });
  span.end();

  res.json(responseBody);
});

/**
 * GET /health
 * Liveness check for docker-compose and ACA
 */
app.get("/health", (_req, res) => {
  res.json({ status: "ok" });
});

app.listen(PORT, () => {
  console.log(`[mock-backend] Listening on port ${PORT}`);
  console.log(`[mock-backend] Service name: ${process.env.OTEL_SERVICE_NAME || "mock-backend"}`);
});
