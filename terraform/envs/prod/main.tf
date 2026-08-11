terraform {
  required_version = ">= 1.15"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 7.0"
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
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
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
  ])
  service            = each.value
  disable_on_destroy = false
}

data "google_project" "project" {
  project_id = var.project_id
}

# Artifact Registry (Docker リポジトリ)
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  project       = var.project_id
  repository_id = "docker"
  format        = "DOCKER"
  description   = "Application container images"

  depends_on = [google_project_service.apis]
}

# ============================================================
# VPC + サブネット
#
# CIDR 配分計画:
#   10.0.0.0/16    — ユーザー管理サブネット
#     10.0.1.0/26  — Cloud Run UI (Direct VPC Egress, 将来の動的 UI 用)
#     10.0.1.64/26 — Cloud Run backend  (Direct VPC Egress)
#     10.0.2.0/28  — PSC NEG (Apigee → LB 接続用)
#   10.100.0.0/22  — Apigee X ランタイム (peering_cidr_range = SLASH_22)
#   10.100.4.0/28  — Apigee X トラブルシューティング (ip_range = /28)
# ============================================================
module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 18.1"

  project_id   = var.project_id
  network_name = "main-vpc"
  routing_mode = "GLOBAL"

  subnets = [
    {
      subnet_name           = "run-ui"
      subnet_ip             = "10.0.1.0/26"
      subnet_region         = var.region
      subnet_private_access = "true"
      description           = "Cloud Run UI - Direct VPC Egress (将来の動的 UI 用)"
    },
    {
      subnet_name           = "run-backend"
      subnet_ip             = "10.0.1.64/26"
      subnet_region         = var.region
      subnet_private_access = "true"
      description           = "Cloud Run backend - Direct VPC Egress"
    },
    {
      subnet_name           = "psc-apigee"
      subnet_ip             = "10.0.2.0/28"
      subnet_region         = var.region
      subnet_private_access = "true"
      subnet_purpose        = "PRIVATE_SERVICE_CONNECT"
      description           = "PSC NEG for Apigee X LB connection"
    },
  ]

  depends_on = [google_project_service.apis]
}

# Cloud Run → Apigee X peering レンジへの HTTPS 通信を許可
resource "google_compute_firewall" "run_to_apigee" {
  name      = "allow-run-to-apigee"
  network   = module.vpc.network_name
  project   = var.project_id
  direction = "EGRESS"
  priority  = 900

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  # Apigee peering レンジのみに限定
  destination_ranges = ["10.100.0.0/22", "10.100.4.0/28"]

  depends_on = [module.vpc]
}


# Apigee X 用プライベート IP レンジ (/22: ランタイム)
resource "google_compute_global_address" "apigee_peering" {
  name          = "apigee-peering-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.100.0.0"
  prefix_length = 22
  network       = module.vpc.network_id
}

# Apigee X 用プライベート IP レンジ (/28: トラブルシューティング)
resource "google_compute_global_address" "apigee_support_range" {
  name          = "apigee-support-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  address       = "10.100.4.0"
  prefix_length = 28
  network       = module.vpc.network_id
}

# サービスネットワーキング ピアリング (/22 と /28 の両方を含める)
resource "google_service_networking_connection" "apigee_peering" {
  network = module.vpc.network_id
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [
    google_compute_global_address.apigee_peering.name,
    google_compute_global_address.apigee_support_range.name,
  ]
  depends_on = [google_project_service.apis]
}

# ============================================================
# 自作モジュール: Cloud Run (フロントエンド)
#
# イメージは CI/CD で更新。Terraform は箱の管理のみ。
# ============================================================
module "frontend" {
  source = "../../modules/cloud-run-service"

  service_name = "frontend-service"
  project_id   = var.project_id
  region       = var.region
  image        = var.frontend_image
  ingress      = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  depends_on = [google_project_service.apis]
}

# ============================================================
# 自作モジュール: Cloud Run (バックエンド)
#
# Apigee (VPC 内部) からのみ受信。
# ============================================================
module "backend" {
  source = "../../modules/cloud-run-service"

  service_name = "backend-service"
  project_id   = var.project_id
  region       = var.region
  image        = var.backend_image
  ingress      = "INGRESS_TRAFFIC_INTERNAL_ONLY"

  # Direct VPC Egress: backend 専用サブネット
  vpc_access = {
    network    = module.vpc.network_id
    subnetwork = module.vpc.subnets["${var.region}/run-backend"].id
    egress     = "PRIVATE_RANGES_ONLY"
  }

  # Apigee cloudservices SA に invoker 権限を付与
  iam_members = [
    {
      role   = "roles/run.invoker"
      member = "serviceAccount:${data.google_project.project.number}@cloudservices.gserviceaccount.com"
    },
  ]

  depends_on = [google_project_service.apis, module.vpc]
}

# ============================================================
# 自作モジュール: Apigee X
# ============================================================
module "apigee" {
  source = "../../modules/apigee"

  project_id         = var.project_id
  region             = var.region
  network_id         = module.vpc.network_id
  support_cidr_range = "10.100.4.0/28"
  # billing_type デフォルト: EVALUATION (即削除可能)
  # 本番移行時は PAYG または SUBSCRIPTION に変更する

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

  project_id           = var.project_id
  oauth2_client_id     = var.iap_oauth_client_id
  oauth2_client_secret = var.iap_oauth_client_secret
}

# ============================================================
# 自作モジュール: External HTTPS LB
# ============================================================
module "lb" {
  source = "../../modules/lb"

  name       = "app"
  project_id = var.project_id
  region     = var.region
  domain     = var.domain

  # UI フロントエンド (Cloud Run + IAP)
  ui_frontends = [
    {
      name                   = "main"
      cloud_run_service_name = module.frontend.service_name
    },
  ]

  # / → /ui/main/ にリダイレクト
  default_ui_redirect = "/ui/main/"

  # IAP 設定 (iap モジュールから取得)
  iap_config = {
    oauth2_client_id     = module.iap.client_id
    oauth2_client_secret = module.iap.client_secret
  }
  iap_allowed_members = var.iap_allowed_members

  # Apigee X 接続 (PSC NEG 経由で /api/* → Apigee にルーティング)
  apigee_config = {
    service_attachment = module.apigee.service_attachment
    network_self_link  = module.vpc.network_self_link
    psc_subnetwork     = module.vpc.subnets["${var.region}/psc-apigee"].self_link
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

  depends_on = [module.apigee]
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
