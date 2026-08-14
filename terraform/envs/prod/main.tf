terraform {
  required_version = ">= 1.15"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.44"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.44"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
  # backend "gcs" { bucket = "..." } # 本番では GCS バックエンドを推奨
}

provider "google" {
  project = var.project_id
  region  = var.regions[0]
}

provider "google-beta" {
  project = var.project_id
  region  = var.regions[0]
}

# 必要 API の有効化
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "compute.googleapis.com",
    "iap.googleapis.com",
    "apigee.googleapis.com",
    "artifactregistry.googleapis.com",
    "servicenetworking.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "dns.googleapis.com",
    "iam.googleapis.com",
    "aiplatform.googleapis.com",
    # 利用ログ非同期パイプライン (Apigee → Pub/Sub → Cloud Run Functions → BigQuery)
    "pubsub.googleapis.com",
    "bigquery.googleapis.com",
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "eventarc.googleapis.com",
    "storage.googleapis.com",
    "logging.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "project" {
  project_id = var.project_id
}

# Artifact Registry (Docker リポジトリ)
resource "google_artifact_registry_repository" "docker" {
  location      = var.regions[0]
  project       = var.project_id
  repository_id = "docker"
  format        = "DOCKER"
  description   = "Application container images"

  depends_on = [google_project_service.apis]
}

# ============================================================
# リージョンごとの CIDR 割当
#
# マルチリージョン拡張時は、ここにリージョンを追記し、
# variables.tf の regions リストにも追加する。
#
# ユーザー管理サブネット (10.0.0.0/16):
#   psc_cidr     — PSC NEG (Apigee → LB 接続用、リージョン毎)
# Apigee peering (10.100.0.0/16):
#   runtime_cidr — ランタイム /22 (リージョン毎)
#   support_cidr — トラブルシューティング /28 (リージョン毎)
# ============================================================
locals {
  # 利用ログ用 Pub/Sub トピック名。
  # vertexai_proxy (publisher) と usage_pipeline (トピック作成) の双方が参照するため、
  # モジュール出力ではなくリテラルで持ち、モジュール間の循環依存を避ける。
  usage_log_topic = "apigee-usage-logs"

  region_networks = {
    "asia-northeast1" = {
      psc_cidr     = "10.0.2.0/28"
      runtime_cidr = "10.100.0.0/22"
      support_cidr = "10.100.4.0/28"
    }
    "asia-northeast2" = {
      psc_cidr     = "10.0.3.0/28"
      runtime_cidr = "10.100.8.0/22"
      support_cidr = "10.100.12.0/28"
    }
  }
}

# ============================================================
# VPC + サブネット
# ============================================================
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.1"

  project_id   = var.project_id
  network_name = "main-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    for r in var.regions : {
      subnet_name           = "psc-apigee-${r}"
      subnet_ip             = local.region_networks[r].psc_cidr
      subnet_region         = r
      subnet_private_access = "true"
      subnet_purpose        = "PRIVATE_SERVICE_CONNECT"
      description           = "PSC NEG for Apigee LB connection"
    }
  ]

  depends_on = [google_project_service.apis]
}

# Apigee 用プライベート IP レンジ (/22: ランタイム) — リージョン毎
resource "google_compute_global_address" "apigee_peering" {
  for_each      = toset(var.regions)
  name          = "apigee-peering-range-${each.key}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(local.region_networks[each.key].runtime_cidr, 0)
  prefix_length = tonumber(split("/", local.region_networks[each.key].runtime_cidr)[1])
  network       = module.vpc.network_id
}

# Apigee 用プライベート IP レンジ (/28: トラブルシューティング) — リージョン毎
resource "google_compute_global_address" "apigee_support_range" {
  for_each      = toset(var.regions)
  name          = "apigee-support-range-${each.key}"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = cidrhost(local.region_networks[each.key].support_cidr, 0)
  prefix_length = tonumber(split("/", local.region_networks[each.key].support_cidr)[1])
  network       = module.vpc.network_id
}

# サービスネットワーキング ピアリング (全リージョンの /22 と /28 を含める)
resource "google_service_networking_connection" "apigee_peering" {
  network = module.vpc.network_id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = concat(
    [for r in var.regions : google_compute_global_address.apigee_peering[r].name],
    [for r in var.regions : google_compute_global_address.apigee_support_range[r].name],
  )
  depends_on = [google_project_service.apis]
}

# ============================================================
# 自作モジュール: Cloud Run (フロントエンド)
#
# イメージは CI/CD で更新。Terraform は箱の管理のみ。
# Cloud Run サービスはリージョナルだが SA はプロジェクト単位のため、
# 全リージョンで単一 SA を共有する。
# ============================================================
resource "google_service_account" "frontend_sa" {
  project      = var.project_id
  account_id   = "frontend-service-sa"
  display_name = "Cloud Run frontend-service SA"

  depends_on = [google_project_service.apis]
}

module "frontend" {
  for_each = toset(var.regions)
  source   = "../../modules/cloud-run-service"

  service_name          = "frontend-service"
  project_id            = var.project_id
  region                = each.key
  image                 = var.frontend_image
  ingress               = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"
  service_account_email = google_service_account.frontend_sa.email

  # IAP SA に Cloud Run invoker 権限を付与 (IAP → Cloud Run 連携に必要)
  iam_members = [
    {
      role   = "roles/run.invoker"
      member = "serviceAccount:${module.iap.service_account_email}"
    },
  ]

  depends_on = [google_project_service.apis, module.iap]
}

# ============================================================
# 自作モジュール: Cloud Run (バックエンド)
#
# Apigee (VPC 内部) からのみ受信。
# ネイティブ マルチリージョン (location=global) で全リージョンに展開。
# Apigee プロキシの target_url は単一 URL のため、引き続き primary の
# service_uri を指す (大阪は warm standby)。
# ============================================================
module "backend" {
  source = "../../modules/cloud-run-service"

  service_name         = "backend-service"
  project_id           = var.project_id
  multi_region_regions = var.regions
  image                = var.backend_image
  ingress              = "INGRESS_TRAFFIC_ALL"

  # Apigee proxy SA に invoker 権限を付与 (IAM で認証・認可を担保)
  iam_members = [
    {
      role   = "roles/run.invoker"
      member = "serviceAccount:${google_service_account.apigee_backend_proxy_sa.email}"
    },
  ]

  depends_on = [google_project_service.apis, google_service_account.apigee_backend_proxy_sa]
}

# ============================================================
# 自作モジュール: Apigee
# ============================================================
module "apigee" {
  source = "../../modules/apigee"

  project_id = var.project_id
  network_id = module.vpc.network_id
  instances = {
    for r in var.regions : r => {
      support_cidr_range = local.region_networks[r].support_cidr
    }
  }
  # billing_type デフォルト: EVALUATION (即削除可能)
  # 本番移行時は PAYG または SUBSCRIPTION に変更する
  #
  # 注意: EVALUATION (評価) 組織は単一リージョンのみ。
  #       マルチリージョン (複数 Apigee インスタンス) は PAYG / SUBSCRIPTION が必要。
  #       regions に 2 つ以上指定する場合は billing_type を変更すること。

  environments = [
    {
      name         = "prod"
      display_name = "Production"
      description  = "Production environment"
      # LB が /api/* のトラフィックを Apigee に転送するため、
      # Apigee は同一ドメインの Host ヘッダーを受け取る
      hostnames = [var.domain]
    }
  ]

  depends_on = [google_service_networking_connection.apigee_peering]
}

# ============================================================
# 自作モジュール: IAP (プロジェクトに 1 つ)
# ============================================================
module "iap" {
  source = "../../modules/iap"

  project_id = var.project_id
}

# ============================================================
# 自作モジュール: External HTTPS LB
# ============================================================
module "lb" {
  source = "../../modules/lb"

  name       = "app"
  project_id = var.project_id
  regions    = var.regions
  domain     = var.domain

  # UI フロントエンド (Cloud Run + IAP)
  ui_frontends = [
    {
      name                   = "main"
      cloud_run_service_name = module.frontend[var.regions[0]].service_name
    },
  ]

  # / → /ui/main/ にリダイレクト
  default_ui_redirect = "/ui/main/"

  iap_config = {
    oauth2_client_id     = var.iap_oauth_client_id
    oauth2_client_secret = var.iap_oauth_client_secret
  }
  iap_allowed_members = var.iap_allowed_members

  # Apigee 接続 (PSC NEG 経由で /api/* → Apigee にルーティング)
  apigee_config = {
    network_self_link = module.vpc.network_self_link
    instances = {
      for r in var.regions : r => {
        service_attachment = module.apigee.service_attachment[r]
        psc_subnetwork     = module.vpc.subnets["${r}/psc-apigee-${r}"].self_link
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    module.frontend,
    module.apigee,
  ]
}

# ============================================================
# 自作モジュール: Apigee Vertex AI プロキシ
# /api/vertexai/v1/models/{model}:{action} → Vertex AI Endpoint
# ============================================================
module "vertexai_proxy" {
  source = "../../modules/apigee-vertexai-proxy"

  project_id       = var.project_id
  project_number   = data.google_project.project.number
  org_id           = module.apigee.org_id
  environment_name = "prod"

  # レスポンスフローからメッセージ・トークン情報を Pub/Sub へ非同期送信
  usage_log_topic             = local.usage_log_topic
  usage_log_include_payloads  = var.usage_log_include_payloads
  usage_log_max_payload_chars = var.usage_log_max_payload_chars

  depends_on = [module.apigee]
}

# ============================================================
# 自作モジュール: 利用ログ非同期パイプライン
# Apigee → Pub/Sub → Cloud Run Functions → BigQuery
# ============================================================
module "usage_pipeline" {
  source = "../../modules/usage-pipeline"

  project_id          = var.project_id
  region              = var.regions[0]
  topic_name          = local.usage_log_topic
  bigquery_location   = var.regions[0]
  function_source_dir = "${path.module}/../../../apps/usage-logger"

  # Vertex AI プロキシの SA にトピックへの publish 権限を付与
  publisher_members = [
    "serviceAccount:${module.vertexai_proxy.service_account_email}",
  ]

  depends_on = [google_project_service.apis]
}

# ============================================================
# Apigee backend-proxy 用 SA (先に作成して backend モジュールから参照可能にする)
# ============================================================
resource "google_service_account" "apigee_backend_proxy_sa" {
  project      = var.project_id
  account_id   = "apigee-backend-proxy-sa"
  display_name = "Apigee backend Proxy SA"

  depends_on = [google_project_service.apis]
}

# ============================================================
# 自作モジュール: Apigee サービスプロキシ (汎用)
# /api/{service_name}/* → Cloud Run サービス
# ============================================================
module "backend_proxy" {
  source = "../../modules/apigee-service-proxy"

  project_id       = var.project_id
  project_number   = data.google_project.project.number
  org_id           = module.apigee.org_id
  environment_name = "prod"
  service_name     = "backend"
  target_url       = module.backend.service_uri
  proxy_sa_email   = google_service_account.apigee_backend_proxy_sa.email

  depends_on = [module.apigee, module.backend]
}

# ============================================================
# 公式モジュール: Cloud DNS ゾーン + A レコード
# ============================================================
module "dns" {
  source  = "terraform-google-modules/cloud-dns/google"
  version = "~> 7.0"

  project_id = var.project_id
  type       = "public"
  name       = replace(var.domain, ".", "-")
  domain     = "${var.domain}."

  recordsets = [
    {
      name    = ""
      type    = "A"
      ttl     = 300
      records = [module.lb.ip_address]
    },
  ]

  depends_on = [google_project_service.apis, module.lb]
}

# ============================================================
# 自作モジュール: GitHub Actions Workload Identity Federation
#
# OSS セキュリティ:
#   - main ブランチの push イベントのみデプロイ可能
#   - fork からの PR ではトークン取得不可
# ============================================================
module "github_wif" {
  source = "../../modules/github-wif"

  project_id     = var.project_id
  github_repo    = var.github_repo
  allowed_branch = "main"

  depends_on = [google_project_service.apis]
}
