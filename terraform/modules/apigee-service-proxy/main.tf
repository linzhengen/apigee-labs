terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}

# ============================================================
# サービスプロキシ専用サービスアカウント
# proxy_sa_email が指定されている場合は外部 SA を使用し、内部作成をスキップ
# ============================================================
locals {
  proxy_sa_email = coalesce(var.proxy_sa_email, try(google_service_account.proxy_sa[0].email, null))
}

resource "google_service_account" "proxy_sa" {
  count        = var.proxy_sa_email == null ? 1 : 0
  project      = var.project_id
  account_id   = "apigee-${var.service_name}-proxy-sa"
  display_name = "Apigee ${var.service_name} Proxy SA"
}

# Apigee ランタイムがこの SA のトークンを取得するために必要
resource "google_service_account_iam_member" "apigee_token_creator" {
  service_account_id = var.proxy_sa_email != null ? "projects/${var.project_id}/serviceAccounts/${var.proxy_sa_email}" : google_service_account.proxy_sa[0].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-apigee.iam.gserviceaccount.com"
}

# ============================================================
# プロキシバンドルを zip 化
# service_name と target_url を templatefile で埋め込む
# ============================================================
data "archive_file" "proxy_bundle" {
  type        = "zip"
  output_path = "${path.module}/${var.service_name}-proxy.zip"

  source {
    content = templatefile("${path.module}/bundle/apiproxy/apiproxy.xml.tpl", {
      service_name = var.service_name
    })
    filename = "apiproxy/apiproxy.xml"
  }

  source {
    content = templatefile("${path.module}/bundle/apiproxy/proxies/default.xml.tpl", {
      service_name = var.service_name
    })
    filename = "apiproxy/proxies/default.xml"
  }

  source {
    content = templatefile("${path.module}/bundle/apiproxy/targets/default.xml.tpl", {
      target_url = var.target_url
    })
    filename = "apiproxy/targets/default.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-RemoveClientAuth.xml")
    filename = "apiproxy/policies/AM-RemoveClientAuth.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-SetTargetPath.xml")
    filename = "apiproxy/policies/AM-SetTargetPath.xml"
  }
}

# ============================================================
# Apigee API プロキシ (バンドルをアップロード)
# ============================================================
resource "google_apigee_api" "proxy" {
  org_id         = var.org_id
  name           = "${var.service_name}-proxy"
  config_bundle  = data.archive_file.proxy_bundle.output_path
  detect_md5hash = data.archive_file.proxy_bundle.output_md5

  depends_on = [google_service_account_iam_member.apigee_token_creator]
}

# ============================================================
# プロキシを環境にデプロイ
# ============================================================
resource "google_apigee_api_deployment" "proxy" {
  org_id          = google_apigee_api.proxy.org_id
  environment     = var.environment_name
  proxy_id        = google_apigee_api.proxy.name
  revision        = google_apigee_api.proxy.latest_revision_id
  service_account = local.proxy_sa_email
}
