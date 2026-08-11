<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  Vertex AI エンドポイント向けにリクエストパスを書き換える。

  グローバル変換例:
    受信: POST /api/vertexai/v1/models/gemini-2.0-flash:generateContent
    送信: POST https://aiplatform.googleapis.com/v1/projects/${project_id}/locations/global/publishers/google/models/gemini-2.0-flash:generateContent

  リージョン指定時の変換例:
    受信: POST /api/vertexai/v1/locations/asia-northeast1/models/gemini-2.0-flash:generateContent
    送信: POST https://asia-northeast1-aiplatform.googleapis.com/v1/projects/${project_id}/locations/asia-northeast1/publishers/google/models/gemini-2.0-flash:generateContent

  {targetRegion} が未設定の場合は "global" にフォールバック。
  {modelAction} は EV-ExtractModelPath で抽出されたフロー変数。
  $${project_id} は Terraform が "${project_id}" に展開済み。
-->
<AssignMessage name="AM-SetTargetPath">
  <AssignTo createNew="false" type="request"/>
  <Set>
    <Path>/v1/projects/${project_id}/locations/{resolvedRegion}/publishers/google/models/{modelAction}</Path>
  </Set>
</AssignMessage>
