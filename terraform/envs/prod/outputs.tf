output "lb_ip_address" {
  description = "DNS A レコードに設定する LB の静的 IP"
  value       = module.lb.ip_address
}

output "frontend_url" {
  description = "フロントエンド Cloud Run URL"
  value       = module.frontend.service_uri
}

output "backend_url" {
  description = "バックエンド Cloud Run URL"
  value       = module.backend.service_uri
}

output "vertexai_proxy_endpoint" {
  description = "Vertex AI プロキシのエンドポイント"
  value       = "https://${var.domain}/api/vertexai/v1/models/{model}:generateContent"
}
