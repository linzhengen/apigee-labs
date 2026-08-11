<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<APIProxy name="${service_name}-proxy" revision="1">
  <Description>${service_name} service proxy - routes to Cloud Run via Apigee</Description>
  <BasePaths>/api/${service_name}</BasePaths>
  <Policies>
    <Policy>AM-RemoveClientAuth</Policy>
    <Policy>AM-SetTargetPath</Policy>
  </Policies>
  <ProxyEndpoints>
    <ProxyEndpoint>default</ProxyEndpoint>
  </ProxyEndpoints>
  <TargetEndpoints>
    <TargetEndpoint>default</TargetEndpoint>
  </TargetEndpoints>
</APIProxy>
