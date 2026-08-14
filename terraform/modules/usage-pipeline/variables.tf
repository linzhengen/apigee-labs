variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "Cloud Run Functions / Eventarc トリガーのリージョン"
  type        = string
}

variable "topic_name" {
  description = "利用ログを受け取る Pub/Sub トピック名 (Apigee プロキシの送信先と一致させる)"
  type        = string
  default     = "apigee-usage-logs"
}

variable "message_retention_duration" {
  description = "Pub/Sub トピックのメッセージ保持期間 (秒表記)"
  type        = string
  default     = "86400s"
}

variable "publisher_members" {
  description = "トピックへの publish を許可する IAM メンバー (例: serviceAccount:apigee-vertexai-proxy-sa@...)"
  type        = list(string)
  default     = []
}

variable "dataset_id" {
  description = "BigQuery データセット ID"
  type        = string
  default     = "apigee_usage"
}

variable "table_id" {
  description = "BigQuery テーブル ID"
  type        = string
  default     = "vertexai_usage_logs"
}

variable "bigquery_location" {
  description = "BigQuery データセットのロケーション"
  type        = string
  default     = "asia-northeast1"
}

variable "partition_expiration_days" {
  description = "パーティションの保持日数 (0 で無期限)"
  type        = number
  default     = 365
}

variable "delete_contents_on_destroy" {
  description = "terraform destroy 時にデータセット内のテーブルも削除するか"
  type        = bool
  default     = false
}

variable "function_name" {
  description = "Cloud Run Functions の関数名"
  type        = string
  default     = "usage-logger"
}

variable "function_source_dir" {
  description = "関数ソースのディレクトリパス"
  type        = string
}

variable "max_instance_count" {
  description = "関数の最大インスタンス数"
  type        = number
  default     = 10
}
