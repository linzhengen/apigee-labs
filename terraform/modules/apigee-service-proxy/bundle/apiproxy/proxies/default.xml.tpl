<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<ProxyEndpoint name="default">
  <HTTPProxyConnection>
    <BasePath>/api/${service_name}</BasePath>
  </HTTPProxyConnection>

  <PreFlow name="PreFlow">
    <Request>
      <!-- クライアントの認証情報を除去 (Apigee がターゲット向けトークンを付与) -->
      <Step><Name>AM-RemoveClientAuth</Name></Step>

      <!-- BasePath 以降のパスをそのままターゲットに転送 -->
      <Step><Name>AM-SetTargetPath</Name></Step>
    </Request>
    <Response/>
  </PreFlow>

  <RouteRule name="default">
    <TargetEndpoint>default</TargetEndpoint>
  </RouteRule>
</ProxyEndpoint>
