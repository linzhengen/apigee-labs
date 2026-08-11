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

variable "service_name" {
  description = "サービス名 (BasePath: /api/{service_name}, SA: apigee-{service_name}-proxy-sa)"
  type        = string
}

variable "target_url" {
  description = "ターゲット Cloud Run サービスの URL (例: https://backend-service-xxx.a.run.app)"
  type        = string
}
