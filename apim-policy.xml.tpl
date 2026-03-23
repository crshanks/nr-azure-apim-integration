<!--
  APIM Policy Template — rendered by demo/terraform/main.tf
  Variables injected by Terraform:
    logger_id  : name of the azurerm_api_management_logger (e.g. apim-eventhub-logger)
    backend_id : name of the azurerm_api_management_backend (e.g. mock-backend)

  Trace correlation strategy (bulletproof — works with diagnostics ON or OFF):

  INBOUND:
    - Extract traceId and clientSpanId from the incoming traceparent (or seed new ones).
    - Always generate a manual APIM span ID (manualApimSpanId) and explicitly set it
      on the traceparent header sent to the backend.
    - If APIM diagnostics are OFF: this manual header reaches the backend unchanged.
    - If APIM diagnostics are ON: APIM's native W3C engine overwrites it with its own
      span ID — that's fine, outbound captures the truth either way.

  OUTBOUND:
    - Read context.Request.Headers["traceparent"] — this is the exact header that was
      sent to the backend (either our manual one or APIM's native one).
    - Parse the span ID from it (finalApimSpanId) and use it in the Event Hub payload.
    - This guarantees the logged Id matches the backend's parentId regardless of
      whether diagnostics are enabled.

  OTel Collector strategy:
    The azure_event_hub receiver (format: "azure") natively parses Azure Application
    Insights AppRequests records into OTel spans via a traces pipeline. The payload
    is structured to match that schema:
      OperationId → trace.id
      Id          → span.id          (the actual span ID sent to the backend)
      ParentId    → span.parentSpanId
      Name        → span.name
      AppRoleName → service.name (resource attribute, synthesized as entity in NR)
      DurationMs  → end_time = start_time + DurationMs
      ResultCode  → http.response.status_code
      Url         → http.url
      Properties["HTTP Method"] → http.method
-->
<policies>
  <inbound>
    <!-- CORS — must be first, before <base />, to handle preflight OPTIONS requests -->
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>*</origin>
      </allowed-origins>
      <allowed-methods>
        <method>GET</method>
        <method>OPTIONS</method>
      </allowed-methods>
      <allowed-headers>
        <header>traceparent</header>
        <header>tracestate</header>
        <header>content-type</header>
      </allowed-headers>
    </cors>

    <base />

    <!-- Route to the demo mock-backend registered in Terraform -->
    <set-backend-service backend-id="${backend_id}" />

    <!--
      STEP 1: Extract traceId and clientSpanId from the inbound traceparent,
      or seed new values if no traceparent was provided.
    -->
    <choose>
      <when condition="@(context.Request.Headers.ContainsKey("traceparent"))">
        <set-variable name="inboundTraceparent" value="@(context.Request.Headers.GetValueOrDefault("traceparent", ""))" />
        <set-variable name="traceId" value="@{
          var tp = context.Variables.GetValueOrDefault<string>("inboundTraceparent", "");
          var parts = tp.Split('-');
          return (parts.Length == 4) ? parts[1] : Guid.NewGuid().ToString("N");
        }" />
        <set-variable name="clientSpanId" value="@{
          var tp = context.Variables.GetValueOrDefault<string>("inboundTraceparent", "");
          var parts = tp.Split('-');
          return (parts.Length == 4) ? parts[2] : "0000000000000000";
        }" />
        <set-variable name="traceFlags" value="@{
          var tp = context.Variables.GetValueOrDefault<string>("inboundTraceparent", "");
          var parts = tp.Split('-');
          return (parts.Length == 4) ? parts[3] : "01";
        }" />
      </when>
      <otherwise>
        <set-variable name="traceId" value="@(Guid.NewGuid().ToString("N"))" />
        <set-variable name="clientSpanId" value="0000000000000000" />
        <set-variable name="traceFlags" value="01" />
      </otherwise>
    </choose>

    <!--
      STEP 2: Always generate a manual APIM span ID and explicitly set the
      traceparent header. If diagnostics are OFF this reaches the backend as-is.
      If diagnostics are ON, APIM's native engine overwrites it — outbound captures
      whichever span ID was actually sent.
    -->
    <set-variable name="manualApimSpanId" value="@{
      var bytes = new byte[8];
      new System.Random().NextBytes(bytes);
      return BitConverter.ToString(bytes).Replace("-", "").ToLower();
    }" />
    <set-header name="traceparent" exists-action="override">
      <value>@(string.Format("00-{0}-{1}-{2}",
        context.Variables.GetValueOrDefault<string>("traceId"),
        context.Variables.GetValueOrDefault<string>("manualApimSpanId"),
        context.Variables.GetValueOrDefault<string>("traceFlags")))</value>
    </set-header>

    <choose>
      <when condition="@(context.Request.Headers.ContainsKey("tracestate"))">
        <set-header name="tracestate" exists-action="override">
          <value>@(context.Request.Headers.GetValueOrDefault("tracestate", ""))</value>
        </set-header>
      </when>
    </choose>

  </inbound>

  <backend>
    <base />
  </backend>

  <outbound>
    <base />

    <!--
      STEP 3: Capture the traceparent that was actually sent to the backend.
      This is the source of truth — either our manual span ID (diagnostics OFF)
      or APIM's natively-generated span ID (diagnostics ON).
    -->
    <set-variable name="finalApimSpanId" value="@{
      var tp = context.Request.Headers.GetValueOrDefault("traceparent", "");
      var parts = tp.Split('-');
      return (parts.Length == 4) ? parts[2] : context.Variables.GetValueOrDefault<string>("manualApimSpanId", "0000000000000000");
    }" />

    <!--
      STEP 4: Emit an Azure Application Insights AppRequests record to Event Hub.
      The azure_event_hub receiver (format: "azure") maps this to a native OTel span
      in the traces pipeline.
    -->
    <log-to-eventhub logger-id="${logger_id}" partition-id="0">
      @{
        var traceId      = context.Variables.GetValueOrDefault<string>("traceId", "");
        var clientSpanId = context.Variables.GetValueOrDefault<string>("clientSpanId", "0000000000000000");
        var finalSpanId  = context.Variables.GetValueOrDefault<string>("finalApimSpanId", "");
        var method       = context.Request.Method;
        var url          = context.Request.Url.ToString();
        var statusCode   = context.Response.StatusCode.ToString();
        var durationMs   = context.Elapsed.TotalMilliseconds;
        var timestamp    = DateTime.UtcNow.ToString("o");

        var record = new JObject(
          new JProperty("time",        timestamp),
          new JProperty("resourceId",  context.Deployment.ServiceId),
          new JProperty("Type",        "AppRequests"),
          new JProperty("OperationId", traceId),
          new JProperty("Id",          finalSpanId),
          new JProperty("ParentId",    clientSpanId),
          new JProperty("Name",        context.Operation.Name),
          new JProperty("AppRoleName", "apim-gateway"),
          new JProperty("DurationMs",  durationMs),
          new JProperty("ResultCode",  statusCode),
          new JProperty("Url",         url),
          new JProperty("Properties",  new JObject(
            new JProperty("HTTP Method", method)
          ))
        );
        return new JObject(new JProperty("records", new JArray(record))).ToString();
      }
    </log-to-eventhub>

  </outbound>

  <on-error>
    <base />
  </on-error>
</policies>
