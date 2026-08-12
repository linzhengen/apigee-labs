output "proxy_name" {
  description = "Apigee プロキシ名"
  value       = google_apigee_api.proxy.name
}

output "proxy_revision" {
  description = "デプロイされたプロキシのリビジョン"
  value       = google_apigee_api.proxy.latest_revision_id
}

output "proxy_base_path" {
  description = "プロキシのベースパス"
  value       = "/api/${var.service_name}"
}

output "service_account_email" {
  description = "プロキシ用サービスアカウントのメールアドレス"
  value       = local.proxy_sa_email
}
