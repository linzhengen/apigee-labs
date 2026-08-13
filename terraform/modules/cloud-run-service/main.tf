# ============================================================
# Cloud Run サービス
#
# Terraform はサービスの「箱」(ingress / VPC / IAM) を管理し、
# コンテナイメージの更新は CI/CD に委譲する (ignore_changes)。
# サービスごとに専用 SA を作成し、最小権限の原則を適用する。
# ============================================================

# サービス専用サービスアカウント
# service_account_email 指定時は外部 SA を使用し、内部作成をスキップ (マルチリージョンで共有)
resource "google_service_account" "this" {
  count        = var.service_account_email == null ? 1 : 0
  project      = var.project_id
  account_id   = "${var.service_name}-sa"
  display_name = "Cloud Run ${var.service_name} SA"
}

locals {
  sa_email = coalesce(var.service_account_email, try(google_service_account.this[0].email, null))

  # ネイティブ マルチリージョン (location=global) は 2 リージョン以上が必須。
  # 1 リージョンの場合は通常の単一リージョン サービスとして扱う。
  multi_region_enabled = var.multi_region_regions != null && length(var.multi_region_regions) > 1
  location             = local.multi_region_enabled ? "global" : (var.multi_region_regions != null ? var.multi_region_regions[0] : var.region)
}

# Artifact Registry からイメージを Pull するための権限 (必須)
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.sa_email}"
}

# SA に付与する追加ロール (将来の拡張用)
resource "google_project_iam_member" "sa_roles" {
  for_each = toset(var.service_account_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${local.sa_email}"
}

resource "google_cloud_run_v2_service" "this" {
  name                = var.service_name
  location            = local.location
  project             = var.project_id
  ingress             = var.ingress
  deletion_protection = false

  dynamic "multi_region_settings" {
    for_each = local.multi_region_enabled ? [1] : []
    content {
      regions = var.multi_region_regions
    }
  }

  template {
    service_account = local.sa_email

    containers {
      image = var.image
      ports {
        container_port = var.container_port
      }
    }

    dynamic "vpc_access" {
      for_each = var.vpc_access != null ? [var.vpc_access] : []
      content {
        network_interfaces {
          network    = vpc_access.value.network
          subnetwork = vpc_access.value.subnetwork
        }
        egress = vpc_access.value.egress
      }
    }
  }

  lifecycle {
    ignore_changes = [
      template[0].containers[0].image,
      client,
      client_version,
    ]
  }

}

# IAM メンバーの付与 (invoker 等: 外部からこのサービスを呼ぶ側の権限)
resource "google_cloud_run_v2_service_iam_member" "this" {
  for_each = { for idx, iam in var.iam_members : idx => iam }

  project  = var.project_id
  location = local.location
  name     = google_cloud_run_v2_service.this.name
  role     = each.value.role
  member   = each.value.member
}
