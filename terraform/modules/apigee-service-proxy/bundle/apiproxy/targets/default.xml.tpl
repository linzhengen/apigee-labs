<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<TargetEndpoint name="default">
  <HTTPTargetConnection>
    <!--
      Cloud Run サービス URL (Terraform で埋め込み)
      Cloud Run の ingress が INTERNAL_ONLY の場合、Apigee (同一プロジェクト) からのみアクセス可能。
    -->
    <URL>${target_url}</URL>

    <!--
      GoogleAuthentication: Apigee ランタイム SA がアクセストークンを自動取得。
    -->
    <Authentication>
      <GoogleAccessToken>
        <Scopes>
          <Scope>https://www.googleapis.com/auth/cloud-platform</Scope>
        </Scopes>
      </GoogleAccessToken>
    </Authentication>
  </HTTPTargetConnection>
</TargetEndpoint>
