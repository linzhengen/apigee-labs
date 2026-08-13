output "org_id" {
  description = "Apigee Organization ID (プレフィックスなし)"
  value       = google_apigee_organization.this.name
}

output "instance_host" {
  description = "Apigee インスタンスのプライベート IP (VPC ルーティング用) のマップ (キー = リージョン)"
  value       = { for k, v in google_apigee_instance.this : k => v.host }
}

output "instance_id" {
  description = "Apigee インスタンス ID のマップ (キー = リージョン)"
  value       = { for k, v in google_apigee_instance.this : k => v.id }
}

output "service_attachment" {
  description = "Apigee インスタンスの PSC サービスアタッチメントのマップ (キー = リージョン)"
  value       = { for k, v in google_apigee_instance.this : k => v.service_attachment }
}

output "environment_names" {
  description = "作成された Apigee 環境名のマップ"
  value       = { for k, v in google_apigee_environment.this : k => v.name }
}
