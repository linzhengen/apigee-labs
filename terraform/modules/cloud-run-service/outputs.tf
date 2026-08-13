output "service_name" {
  description = "Cloud Run サービス名"
  value       = google_cloud_run_v2_service.this.name
}

output "service_uri" {
  description = "Cloud Run サービス URL"
  value       = google_cloud_run_v2_service.this.uri
}

output "service_id" {
  description = "Cloud Run サービス ID"
  value       = google_cloud_run_v2_service.this.id
}

output "service_account_email" {
  description = "サービス専用サービスアカウントのメールアドレス"
  value       = local.sa_email
}
