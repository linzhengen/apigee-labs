variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "oauth2_client_id" {
  description = "IAP 用 OAuth 2.0 クライアント ID (GCP Console で作成)"
  type        = string
  sensitive   = true
}

variable "oauth2_client_secret" {
  description = "IAP 用 OAuth 2.0 クライアントシークレット (GCP Console で作成)"
  type        = string
  sensitive   = true
}
