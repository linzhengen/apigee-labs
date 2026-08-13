variable "name" {
  description = "LB リソース名のプレフィックス"
  type        = string
}

variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "regions" {
  description = "UI Serverless NEG / Apigee PSC NEG を配置するリージョン一覧"
  type        = list(string)
}

variable "domain" {
  description = "マネージド SSL 証明書に使うドメイン"
  type        = string
}

# ============================================================
# UI フロントエンド設定 (複数対応: 全て Cloud Run)
# ============================================================
variable "ui_frontends" {
  description = <<-EOT
    UI フロントエンドの一覧。パスベースで /ui/{name}/* にルーティング。
    全て Cloud Run Backend Service として作成し、IAP で保護。
  EOT
  type = list(object({
    name                   = string # パス名 (例: "main" → /ui/main/*)
    cloud_run_service_name = string # Cloud Run サービス名
  }))
  default = []
}

# デフォルトリダイレクト先 (/ → /ui/{default_ui_redirect}/)
variable "default_ui_redirect" {
  description = "/ にアクセスした場合のリダイレクト先パス (例: /ui/main/)"
  type        = string
  default     = "/ui/main/"
}

# IAP 設定 (null の場合は全 Backend Service で IAP 無効)
variable "iap_config" {
  description = "IAP OAuth 設定。指定時は全 Backend Service (UI + Apigee) に IAP を有効化する"
  type = object({
    oauth2_client_id     = string
    oauth2_client_secret = string
  })
  default   = null
  sensitive = true
}

variable "iap_allowed_members" {
  description = "IAP アクセス許可メンバーのリスト (例: user:foo@example.com)"
  type        = list(string)
  default     = []
}

# Apigee 接続 (null の場合は /api/* ルーティングなし)
variable "apigee_config" {
  description = "Apigee 接続設定 (PSC NEG)。null の場合は Apigee バックエンドを作成しない"
  type = object({
    network_self_link = string
    instances = map(object({ # キー = リージョン
      service_attachment = string
      psc_subnetwork     = string
    }))
  })
  default = null
}
