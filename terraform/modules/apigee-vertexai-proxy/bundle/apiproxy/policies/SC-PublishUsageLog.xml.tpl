<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!--
  組み立て済みの利用ログを Pub/Sub REST API (topics:publish) へ送信する。

  [Point 1] Response 要素を省略 = fire-and-forget
    レスポンスを待たずに次のステップへ進むため、
    クライアントへのレスポンスタイムに Pub/Sub のレイテンシが加算されない。

  [Point 2] continueOnError="true"
    Pub/Sub 側の障害・タイムアウトが発生してもプロキシはエラーにせず、
    Vertex AI のレスポンスをそのままクライアントへ返却する。

  [Point 3] GoogleAccessToken 認証
    デプロイ時に指定した SA (apigee-vertexai-proxy-sa) の
    アクセストークンを自動付与する。
    SA には対象トピックへの roles/pubsub.publisher が必要
    (usage-pipeline モジュールで付与)。
-->
<ServiceCallout name="SC-PublishUsageLog" continueOnError="true" enabled="true">
  <DisplayName>SC-PublishUsageLog</DisplayName>

  <Request variable="usageLogRequest">
    <Set>
      <Headers>
        <Header name="Content-Type">application/json</Header>
      </Headers>
      <Verb>POST</Verb>
      <Payload contentType="application/json">{usagelog.pubsub.payload}</Payload>
    </Set>
  </Request>

  <!-- Response 要素は意図的に省略 (非同期送信) -->

  <HTTPTargetConnection>
    <URL>https://pubsub.googleapis.com/v1/projects/${project_id}/topics/${topic_name}:publish</URL>
    <Properties>
      <!-- メイン処理を待たせないよう短めに設定 -->
      <Property name="connect.timeout.millis">2000</Property>
      <Property name="io.timeout.millis">3000</Property>
    </Properties>
    <Authentication>
      <GoogleAccessToken>
        <Scopes>
          <Scope>https://www.googleapis.com/auth/pubsub</Scope>
        </Scopes>
      </GoogleAccessToken>
    </Authentication>
  </HTTPTargetConnection>
</ServiceCallout>
