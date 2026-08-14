output "topic_id" {
  description = "利用ログ Pub/Sub トピックの ID"
  value       = google_pubsub_topic.usage_logs.id
}

output "topic_name" {
  description = "利用ログ Pub/Sub トピック名"
  value       = google_pubsub_topic.usage_logs.name
}

output "function_name" {
  description = "Cloud Run Functions の関数名"
  value       = google_cloudfunctions2_function.usage_logger.name
}

output "service_account_email" {
  description = "関数の実行サービスアカウント"
  value       = google_service_account.usage_logger.email
}

output "bigquery_table" {
  description = "利用ログの書き込み先 BigQuery テーブル (project.dataset.table)"
  value       = "${var.project_id}.${google_bigquery_dataset.usage.dataset_id}.${google_bigquery_table.usage_logs.table_id}"
}
