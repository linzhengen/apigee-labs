# ============================================================
# Cloud Run サービス
#
# Terraform はサービスの「箱」(ingress / VPC / IAM) を管理し、
# コンテナイメージの更新は CI/CD に委譲する (ignore_changes)。
# サービスごとに専用 SA を作成し、最小権限の原則を適用する。
# ============================================================

# サービス専用サービスアカウント
resource "google_service_account" "this" {
  project      = var.project_id
  account_id   = "${var.service_name}-sa"
  display_name = "Cloud Run ${var.service_name} SA"
}

# Artifact Registry からイメージを Pull するための権限 (必須)
resource "google_project_iam_member" "artifact_registry_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.this.email}"
}

# SA に付与する追加ロール (将来の拡張用)
resource "google_project_iam_member" "sa_roles" {
  for_each = toset(var.service_account_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.this.email}"
}

resource "google_cloud_run_v2_service" "this" {
  name     = var.service_name
  location = var.region
  project  = var.project_id
  ingress  = var.ingress

  template {
    service_account = google_service_account.this.email

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

  depends_on = var.depends_apis
}

# IAM メンバーの付与 (invoker 等: 外部からこのサービスを呼ぶ側の権限)
resource "google_cloud_run_v2_service_iam_member" "this" {
  for_each = { for iam in var.iam_members : "${iam.role}-${iam.member}" => iam }

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.this.name
  role     = each.value.role
  member   = each.value.member
}
