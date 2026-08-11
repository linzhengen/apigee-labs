variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-northeast1"
}

variable "domain" {
  description = "LB に割り当てるドメイン (例: app.example.com)"
  type        = string
}

variable "iap_support_email" {
  type = string
}

variable "iap_allowed_members" {
  type    = list(string)
  default = []
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
