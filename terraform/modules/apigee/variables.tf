variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "instances" {
  description = "作成する Apigee インスタンスのマップ (キー = リージョン)"
  type = map(object({
    support_cidr_range = string # トラブルシューティング用 /28 (例: 10.100.4.0/28)
  }))
}

variable "network_id" {
  description = "Apigee がピアリングする VPC ネットワークの self_link"
  type        = string
}

variable "analytics_region" {
  description = "Apigee アナリティクスのリージョン (未指定時は instances の先頭キー)"
  type        = string
  default     = ""
}

# EVALUATION の機能制限:
#   - 60 日で自動削除 (延長不可)
#   - 1 インスタンス / 1 ゾーンのみ (高可用性なし)
#   - VPC Service Controls / Private DNS Peering 非対応
#   - セキュリティパッチが最新でない場合あり
#   - Google サポート対象外 (Pre-GA 扱い)
#   - 有料版への変換不可 (PAYG/SUBSCRIPTION は新規作成が必要)
#   - 削除は即座に実行・再作成可能 (retention 設定不要)
variable "billing_type" {
  description = "Apigee の課金タイプ (EVALUATION, PAYG, SUBSCRIPTION)"
  type        = string
  default     = "EVALUATION"
}

# 削除時の動作 (billing_type × retention):
#   EVALUATION                       → 即座に削除・再作成可能
#   PAYG/SUBSCRIPTION + MINIMUM      → 24 時間後に完全削除
#   PAYG/SUBSCRIPTION + デフォルト   → 7 日後に完全削除
# ソフトデリート期間中は同プロジェクトで再作成不可。
variable "retention" {
  description = "Apigee 組織の保持ポリシー (MINIMUM: 24h で削除, DELETION_RETENTION_UNSPECIFIED: 7 日保持)"
  type        = string
  default     = "DELETION_RETENTION_UNSPECIFIED"
}

variable "environments" {
  description = "作成する Apigee 環境の設定リスト"
  type = list(object({
    name         = string
    display_name = optional(string, "")
    description  = optional(string, "")
    hostnames    = list(string)
  }))
}
