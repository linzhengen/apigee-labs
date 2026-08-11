variable "project_id" {
  description = "GCP プロジェクト ID"
  type        = string
}

variable "region" {
  description = "Apigee インスタンスを配置するリージョン"
  type        = string
}

variable "network_id" {
  description = "Apigee がピアリングする VPC ネットワークの self_link"
  type        = string
}

variable "peering_range_name" {
  description = "サービスネットワーキング用に予約済みの IP レンジ名"
  type        = string
}

variable "analytics_region" {
  description = "Apigee アナリティクスのリージョン"
  type        = string
  default     = ""
}

variable "billing_type" {
  description = "Apigee の課金タイプ (PAYG or SUBSCRIPTION)"
  type        = string
  default     = "PAYG"
}

variable "support_cidr_range" {
  description = "Apigee トラブルシューティング用 /28 CIDR レンジ (例: 10.100.4.0/28)"
  type        = string
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
