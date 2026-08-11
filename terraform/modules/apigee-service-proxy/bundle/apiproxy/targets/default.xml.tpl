<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
  <HTTPTargetConnection>
    <!--
      Cloud Run サービス URL (Terraform で埋め込み)
      Cloud Run の ingress が INTERNAL_ONLY の場合、Apigee (同一プロジェクト) からのみアクセス可能。
    -->
    <URL>${target_url}</URL>

    <!--
      GoogleIDToken: Cloud Run は OIDC ID トークンで認証する。
      Audience にはターゲットの Cloud Run サービス URL を指定。
    -->
    <Authentication>
      <GoogleIDToken>
        <Audience>${target_url}</Audience>
      </GoogleIDToken>
    </Authentication>
  </HTTPTargetConnection>
</TargetEndpoint>
