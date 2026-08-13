output "lb_ip_address" {
  description = "DNS A レコードに設定する LB の静的 IP"
  value       = module.lb.ip_address
}

output "frontend_url" {
  description = "フロントエンド Cloud Run URL (primary リージョン)"
  value       = module.frontend[var.regions[0]].service_uri
}

output "backend_url" {
  description = "バックエンド Cloud Run URL"
  value       = module.backend.service_uri
}

output "vertexai_proxy_endpoint" {
  description = "Vertex AI プロキシのエンドポイント"
  value       = "https://${var.domain}/api/vertexai/v1/models/{model}:generateContent"
}

output "dns_name_servers" {
  description = "DNS ゾーンのネームサーバー (ドメインレジストラに設定)"
  value       = module.dns.name_servers
}

output "github_wif_provider" {
  description = "GitHub Actions vars.WORKLOAD_IDENTITY_PROVIDER に設定する値"
  value       = module.github_wif.workload_identity_provider
}

output "github_wif_service_account" {
  description = "GitHub Actions vars.GCP_SERVICE_ACCOUNT に設定する値"
  value       = module.github_wif.service_account_email
}
