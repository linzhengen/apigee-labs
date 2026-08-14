variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "project_number" {
  description = "GCP プロジェクト番号 (Apigee ランタイム SA の構築に使用)"
  type        = string
}

variable "org_id" {
  description = "Apigee Organization ID"
  type        = string
}

variable "environment_name" {
  description = "デプロイ先の Apigee 環境名"
  type        = string
}

variable "spike_arrest_rate" {
  description = "ユーザーごとのレート制限 (例: 10ps = 10回/秒, 30pm = 30回/分)"
  type        = string
  default     = "10pm"
}

variable "quota_limit" {
  description = "ユーザーごとのリクエスト数上限"
  type        = number
  default     = 100
}

variable "quota_interval" {
  description = "クォータのインターバル数"
  type        = number
  default     = 1
}

variable "quota_time_unit" {
  description = "クォータの時間単位 (minute / hour / day / week / month)"
  type        = string
  default     = "day"
}

variable "usage_log_topic" {
  description = "利用ログ (メッセージ・トークン数) を非同期送信する Pub/Sub トピック名。空文字の場合は Pub/Sub 連携ポリシーをバンドルに含めない"
  type        = string
  default     = ""
}

variable "usage_log_include_payloads" {
  description = "Pub/Sub へプロンプト・生成文の本文を含めるか。false の場合はメタデータとトークン数のみ送信する"
  type        = bool
  default     = true
}

variable "usage_log_max_payload_chars" {
  description = "Pub/Sub へ送信するプロンプト・生成文の最大文字数 (超過分は切り詰め)"
  type        = number
  default     = 8000
}
