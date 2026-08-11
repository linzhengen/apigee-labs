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
# Apigee がこの SA の権限で Cloud Run を呼び出す
# ============================================================
resource "google_service_account" "proxy_sa" {
  project      = var.project_id
  account_id   = "apigee-${var.service_name}-proxy-sa"
  display_name = "Apigee ${var.service_name} Proxy SA"
}

# Cloud Run invoker 権限
resource "google_project_iam_member" "run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.proxy_sa.email}"
}

# Apigee ランタイムがこの SA のトークンを取得するために必要
resource "google_service_account_iam_member" "apigee_token_creator" {
  service_account_id = google_service_account.proxy_sa.name
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
  org_id        = var.org_id
  name          = "${var.service_name}-proxy"
  config_bundle  = data.archive_file.proxy_bundle.output_path
  detect_md5hash = data.archive_file.proxy_bundle.output_md5

  depends_on = [google_project_iam_member.run_invoker]
}

# ============================================================
# プロキシを環境にデプロイ
# ============================================================
resource "google_apigee_api_deployment" "proxy" {
  org_id          = google_apigee_api.proxy.org_id
  environment     = var.environment_name
  proxy_id        = google_apigee_api.proxy.name
  revision        = google_apigee_api.proxy.latest_revision_id
  service_account = google_service_account.proxy_sa.email
}
