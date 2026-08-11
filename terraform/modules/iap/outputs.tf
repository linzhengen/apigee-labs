output "client_id" {
  description = "IAP OAuth クライアント ID"
  value       = var.oauth2_client_id
  sensitive   = true
}

output "client_secret" {
  description = "IAP OAuth クライアントシークレット"
  value       = var.oauth2_client_secret
  sensitive   = true
}

output "service_account_email" {
  description = "IAP サービスアカウント email"
  value       = google_project_service_identity.iap.email
}
