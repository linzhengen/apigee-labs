variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "github_repo" {
  description = "GitHub リポジトリ (例: owner/repo)"
  type        = string
}

# OSS セキュリティ: デプロイを許可するブランチを制限
# fork からの PR や feature ブランチからはデプロイ不可
variable "allowed_branch" {
  description = "WIF でデプロイを許可するブランチ名"
  type        = string
  default     = "main"
}
