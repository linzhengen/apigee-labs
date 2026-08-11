variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "support_email" {
  description = "IAP OAuth 同意画面のサポートメール"
  type        = string
}

variable "application_title" {
  description = "IAP OAuth 同意画面のアプリケーション名"
  type        = string
  default     = "IAP Protected App"
}

variable "display_name" {
  description = "OAuth クライアントの表示名"
  type        = string
  default     = "IAP OAuth Client"
}
