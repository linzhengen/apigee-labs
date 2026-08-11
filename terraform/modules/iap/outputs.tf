output "client_id" {
  description = "IAP OAuth クライアント ID"
  value       = google_iap_client.this.client_id
  sensitive   = true
}

output "client_secret" {
  description = "IAP OAuth クライアントシークレット"
  value       = google_iap_client.this.secret
  sensitive   = true
}

output "brand_name" {
  description = "IAP ブランド名 (既存 brand を import する際に使用)"
  value       = google_iap_brand.this.name
}
