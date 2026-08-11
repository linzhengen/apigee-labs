output "workload_identity_provider" {
  description = "GitHub Actions の workload_identity_provider に設定する値"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "GitHub Actions の service_account に設定する値"
  value       = google_service_account.github_actions.email
}
