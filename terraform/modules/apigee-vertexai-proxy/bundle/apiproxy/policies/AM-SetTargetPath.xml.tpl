<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  Vertex AI エンドポイント向けに target.url をフルURLで設定。
  TargetEndpoint PreFlow で実行し、pathsuffix 自動コピーを上書きする。

  project_id は常に Terraform 値 (${project_id}) を使用。
  publisher は google 固定。
  リージョンは AM-SetRegionalHost (resolvedHost) と AM-ResolveRegion (resolvedRegion) で決定済み。
-->
<AssignMessage name="AM-SetTargetPath">
  <AssignTo createNew="false" type="request"/>
  <AssignVariable>
    <Name>target.url</Name>
    <Template>https://{resolvedHost}/v1/projects/${project_id}/locations/{resolvedRegion}/publishers/google/models/{modelAction}</Template>
  </AssignVariable>
</AssignMessage>
