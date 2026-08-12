output "service_account_email" {
  description = "IAP サービスアカウント email"
  value       = google_project_service_identity.iap.email
}
