<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  Vertex AI エンドポイント向けに target.url をフルURLで設定。
  TargetEndpoint PreFlow で実行し、pathsuffix 自動コピーを上書きする。
  <Template> はメッセージテンプレート構文を解釈するため {variable} が展開される。
-->
<AssignMessage name="AM-SetTargetPath">
  <AssignTo createNew="false" type="request"/>
  <AssignVariable>
    <Name>target.url</Name>
    <Template>https://{resolvedHost}/v1/projects/${project_id}/locations/{resolvedRegion}/publishers/google/models/{modelAction}</Template>
  </AssignVariable>
</AssignMessage>
