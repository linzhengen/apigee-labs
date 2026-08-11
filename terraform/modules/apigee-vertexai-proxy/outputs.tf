output "proxy_name" {
  description = "Apigee プロキシ名"
  value       = google_apigee_api.vertexai_proxy.name
}

output "proxy_revision" {
  description = "デプロイされたプロキシのリビジョン"
  value       = google_apigee_api.vertexai_proxy.latest_revision_id
}

output "proxy_base_path" {
  description = "プロキシのベースパス"
  value       = "/api/vertexai"
}

output "service_account_email" {
  description = "Vertex AI プロキシ用サービスアカウントのメールアドレス"
  value       = google_service_account.vertexai_proxy_sa.email
}
