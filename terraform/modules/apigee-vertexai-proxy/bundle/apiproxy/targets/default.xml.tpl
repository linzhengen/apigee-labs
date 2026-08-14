<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
  <PreFlow name="PreFlow">
    <Request>
      <!-- target.url をフル URL に上書き (常に Terraform の project_id を使用) -->
      <Step><Name>AM-SetTargetPath</Name></Step>
    </Request>
    <Response>
      <!-- レスポンスからトークン使用量を抽出 -->
      <Step>
        <Name>EV-ExtractTokenCounts</Name>
        <Condition>response.content != null</Condition>
      </Step>
      <!-- 配列括弧を除去して数値化 -->
      <Step><Name>AM-CleanTokenCounts</Name></Step>
      <!-- Analytics にトークン数を含む全統計を記録 -->
      <Step><Name>SC-CollectUsageStats</Name></Step>
%{ if usage_log_enabled ~}
      <!-- Pub/Sub 送信用のメッセージ・トークン情報を組み立て -->
      <Step><Name>JS-BuildUsageLog</Name></Step>
      <!-- Pub/Sub へ非同期送信 (fire-and-forget) -->
      <Step>
        <Name>SC-PublishUsageLog</Name>
        <Condition>usagelog.pubsub.payload != null</Condition>
      </Step>
%{ endif ~}
    </Response>
  </PreFlow>

  <HTTPTargetConnection>
    <URL>https://aiplatform.googleapis.com</URL>
    <Authentication>
      <GoogleAccessToken>
        <Scopes>
          <Scope>https://www.googleapis.com/auth/cloud-platform</Scope>
        </Scopes>
      </GoogleAccessToken>
    </Authentication>
  </HTTPTargetConnection>
</TargetEndpoint>
