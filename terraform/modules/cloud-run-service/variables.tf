variable "service_name" {
  description = "Cloud Run サービス名"
  type        = string
}

variable "service_account_email" {
  description = "既存 SA の email。指定時はモジュール内で SA を作成しない（マルチリージョンで共有する場合に使用）"
  type        = string
  default     = null
}

variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "Cloud Run リージョン (multi_region_regions 指定時は不要)"
  type        = string
  default     = null
}

variable "multi_region_regions" {
  description = "Cloud Run ネイティブ マルチリージョンの展開リージョン一覧。2 リージョン以上で location=global のマルチリージョンになり、1 リージョンなら単一リージョン サービスとして扱われる (region を指定した場合と同じ)"
  type        = list(string)
  default     = null
}

variable "image" {
  description = "初回デプロイ用コンテナイメージ (以降は CI/CD で更新)"
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

variable "container_port" {
  description = "コンテナのリッスンポート"
  type        = number
  default     = 8080
}

variable "ingress" {
  description = "Ingress 設定 (INGRESS_TRAFFIC_ALL, INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER, INGRESS_TRAFFIC_INTERNAL_ONLY)"
  type        = string
  default     = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
}

variable "vpc_access" {
  description = "Direct VPC Egress 設定 (null の場合は VPC 接続なし)"
  type = object({
    network    = string
    subnetwork = string
    egress     = string
  })
  default = null
}

variable "service_account_roles" {
  description = "サービス SA に付与するロール (例: roles/aiplatform.user)"
  type        = list(string)
  default     = []
}

variable "iam_members" {
  description = "Cloud Run サービスに付与する IAM メンバーのリスト"
  type = list(object({
    role   = string
    member = string
  }))
  default = []
}

