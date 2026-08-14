<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  Pub/Sub へ送信する利用ログ (プロンプト・生成文・トークン数) を組み立て、
  context 変数 usagelog.pubsub.payload に JSON 文字列として格納する。

  continueOnError="true":
    ログ組み立ての失敗でクライアントへのレスポンスを壊さない。
    失敗時は usagelog.pubsub.payload が未設定となり、
    後続の SC-PublishUsageLog は Condition により実行されない。
-->
<Javascript name="JS-BuildUsageLog" continueOnError="true" enabled="true" timeLimit="500">
  <DisplayName>JS-BuildUsageLog</DisplayName>
  <Properties>
    <!-- プロンプト/生成文の最大文字数 (超過分は切り詰め) -->
    <Property name="maxPayloadChars">${usage_log_max_payload_chars}</Property>
    <!-- false にするとメッセージ本文を送らずメタデータ・トークン数のみ記録する -->
    <Property name="includePayloads">${usage_log_include_payloads}</Property>
  </Properties>
  <ResourceURL>jsc://buildUsageLog.js</ResourceURL>
</Javascript>
