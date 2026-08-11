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
