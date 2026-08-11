output "ip_address" {
  description = "LB のグローバル静的 IP アドレス (DNS A レコードに設定)"
  value       = google_compute_global_address.this.address
}
