# ============================================================
# GitHub Actions Workload Identity Federation (OIDC)
#
# OSS セキュリティ考慮:
#   - attribute_condition で対象リポジトリ + ブランチを厳密に制限
#   - fork からの PR ではトークン取得不可 (ref 条件)
#   - CI/CD SA には最小権限のみ付与
# ============================================================

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions OIDC"
  # deletion_policy           = "ABANDON"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-oidc"
  display_name                       = "GitHub OIDC Provider"

  # OSS セキュリティ: 対象リポジトリ + 保護ブランチのみに制限
  # fork からの PR (pull_request イベント) では ref が refs/pull/* になるため拒否される
  attribute_condition = "assertion.repository == '${var.github_repo}' && assertion.ref == 'refs/heads/${var.allowed_branch}'"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.actor"            = "assertion.actor"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# CI/CD 用サービスアカウント
resource "google_service_account" "github_actions" {
  project      = var.project_id
  account_id   = "github-actions"
  display_name = "GitHub Actions CI/CD SA"
}

# SA が WIF 経由でトークンを取得できるようにする
resource "google_service_account_iam_member" "wif_binding" {
  service_account_id = google_service_account.github_actions.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

# CI/CD SA に必要な最小権限
resource "google_project_iam_member" "cicd_roles" {
  for_each = toset([
    "roles/run.developer",           # Cloud Run デプロイ
    "roles/artifactregistry.writer", # Docker イメージ push
    "roles/iam.serviceAccountUser",  # Cloud Run SA の指定
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_actions.email}"
}
