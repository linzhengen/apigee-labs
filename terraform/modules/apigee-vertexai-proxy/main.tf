terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}

# ============================================================
# Vertex AI プロキシ専用サービスアカウント
# google_apigee_api_deployment の service_account に指定し、
# プロキシがこの SA の権限で Vertex AI を呼び出す
# ============================================================
resource "google_service_account" "vertexai_proxy_sa" {
  project      = var.project_id
  account_id   = "apigee-vertexai-proxy-sa"
  display_name = "Apigee Vertex AI Proxy SA"
}

resource "google_project_iam_member" "vertexai_proxy_iam" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.vertexai_proxy_sa.email}"
}

# Apigee ランタイムがこの SA のトークンを取得するために iam.serviceAccountTokenCreator が必要
resource "google_service_account_iam_member" "apigee_token_creator" {
  service_account_id = google_service_account.vertexai_proxy_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${var.project_number}@gcp-sa-apigee.iam.gserviceaccount.com"
}

# ============================================================
# プロキシバンドルを zip 化
# ============================================================
data "archive_file" "proxy_bundle" {
  type        = "zip"
  output_path = "${path.module}/vertexai-proxy.zip"

  source {
    content  = file("${path.module}/bundle/apiproxy/apiproxy.xml")
    filename = "apiproxy/apiproxy.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/proxies/default.xml")
    filename = "apiproxy/proxies/default.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/targets/default.xml")
    filename = "apiproxy/targets/default.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-RemoveClientAuth.xml")
    filename = "apiproxy/policies/AM-RemoveClientAuth.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/EV-ExtractModelPath.xml")
    filename = "apiproxy/policies/EV-ExtractModelPath.xml"
  }

  # project_id を Terraform で埋め込む (Vertex AI のターゲットパス構築用)
  source {
    content = templatefile("${path.module}/bundle/apiproxy/policies/AM-SetTargetPath.xml.tpl", {
      project_id = var.project_id
    })
    filename = "apiproxy/policies/AM-SetTargetPath.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-ResolveRegion.xml")
    filename = "apiproxy/policies/AM-ResolveRegion.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-SetRegionalHost.xml")
    filename = "apiproxy/policies/AM-SetRegionalHost.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/RF-ModelNotFound.xml")
    filename = "apiproxy/policies/RF-ModelNotFound.xml"
  }
}

# ============================================================
# Apigee API プロキシ (バンドルをアップロード)
# ============================================================
resource "google_apigee_api" "vertexai_proxy" {
  org_id          = var.org_id
  name            = "vertexai-proxy"
  config_bundle   = data.archive_file.proxy_bundle.output_path
  detect_md5hash  = data.archive_file.proxy_bundle.output_md5

  depends_on = [google_project_iam_member.vertexai_proxy_iam]
}

# ============================================================
# プロキシを環境にデプロイ (Terraform API で完結)
# ============================================================
resource "google_apigee_api_deployment" "vertexai_proxy" {
  org_id          = google_apigee_api.vertexai_proxy.org_id
  environment     = var.environment_name
  proxy_id        = google_apigee_api.vertexai_proxy.name
  revision        = google_apigee_api.vertexai_proxy.latest_revision_id
  service_account = google_service_account.vertexai_proxy_sa.email
}
