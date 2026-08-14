variable "project_id" {
  type = string
}

variable "regions" {
  description = "frontend / Apigee をデプロイするリージョン一覧 (1 つ目が primary。backend は常に primary)"
  type        = list(string)
  default     = ["asia-northeast1"]
}

variable "domain" {
  description = "LB に割り当てるドメイン (例: app.example.com)"
  type        = string
}

variable "iap_oauth_client_id" {
  description = "IAP 用 OAuth 2.0 クライアント ID (GCP Console で作成)"
  type        = string
  sensitive   = true
}

variable "iap_oauth_client_secret" {
  description = "IAP 用 OAuth 2.0 クライアントシークレット (GCP Console で作成)"
  type        = string
  sensitive   = true
}

variable "iap_allowed_members" {
  type    = list(string)
  default = []
}

variable "github_repo" {
  description = "GitHub リポジトリ (例: owner/apigee-labs)"
  type        = string
}

variable "frontend_image" {
  description = "フロントエンド Cloud Run コンテナイメージ"
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

variable "backend_image" {
  description = "バックエンド Cloud Run コンテナイメージ"
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

variable "usage_log_include_payloads" {
  description = "利用ログにプロンプト・生成文の本文を含めるか (false ならメタデータとトークン数のみ)"
  type        = bool
  default     = true
}

variable "usage_log_max_payload_chars" {
  description = "利用ログに含めるプロンプト・生成文の最大文字数"
  type        = number
  default     = 8000
}
