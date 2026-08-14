terraform {
  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}

locals {
  # usage_log_topic が未指定の場合は Pub/Sub 連携ポリシーをバンドルに含めない
  usage_log_enabled = var.usage_log_topic != ""

  usage_log_files = local.usage_log_enabled ? {
    "apiproxy/policies/JS-BuildUsageLog.xml" = templatefile(
      "${path.module}/bundle/apiproxy/policies/JS-BuildUsageLog.xml.tpl", {
        usage_log_max_payload_chars = var.usage_log_max_payload_chars
        usage_log_include_payloads  = var.usage_log_include_payloads
      }
    )
    "apiproxy/policies/SC-PublishUsageLog.xml" = templatefile(
      "${path.module}/bundle/apiproxy/policies/SC-PublishUsageLog.xml.tpl", {
        project_id = var.project_id
        topic_name = var.usage_log_topic
      }
    )
    "apiproxy/resources/jsc/buildUsageLog.js" = file(
      "${path.module}/bundle/apiproxy/resources/jsc/buildUsageLog.js"
    )
  } : {}
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
    content = templatefile("${path.module}/bundle/apiproxy/apiproxy.xml.tpl", {
      usage_log_enabled = local.usage_log_enabled
    })
    filename = "apiproxy/apiproxy.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/proxies/default.xml")
    filename = "apiproxy/proxies/default.xml"
  }

  source {
    content = templatefile("${path.module}/bundle/apiproxy/targets/default.xml.tpl", {
      usage_log_enabled = local.usage_log_enabled
    })
    filename = "apiproxy/targets/default.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/DJ-DecodeIapJwt.xml")
    filename = "apiproxy/policies/DJ-DecodeIapJwt.xml"
  }

  source {
    content = templatefile("${path.module}/bundle/apiproxy/policies/SA-SpikeArrest.xml.tpl", {
      spike_arrest_rate = var.spike_arrest_rate
    })
    filename = "apiproxy/policies/SA-SpikeArrest.xml"
  }

  source {
    content = templatefile("${path.module}/bundle/apiproxy/policies/QU-PerUserQuota.xml.tpl", {
      quota_limit     = var.quota_limit
      quota_interval  = var.quota_interval
      quota_time_unit = var.quota_time_unit
    })
    filename = "apiproxy/policies/QU-PerUserQuota.xml"
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

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/EV-ExtractTokenCounts.xml")
    filename = "apiproxy/policies/EV-ExtractTokenCounts.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-CleanTokenCounts.xml")
    filename = "apiproxy/policies/AM-CleanTokenCounts.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/SC-CollectUsageStats.xml")
    filename = "apiproxy/policies/SC-CollectUsageStats.xml"
  }

  source {
    content  = file("${path.module}/bundle/apiproxy/policies/AM-AddQuotaHeaders.xml")
    filename = "apiproxy/policies/AM-AddQuotaHeaders.xml"
  }

  # Pub/Sub 非同期連携 (usage_log_topic 指定時のみ)
  dynamic "source" {
    for_each = local.usage_log_files
    content {
      content  = source.value
      filename = source.key
    }
  }
}

# ============================================================
# Apigee API プロキシ (バンドルをアップロード)
# ============================================================
# ============================================================
# DataCollector (Apigee の カスタム Analytics ディメンション)
# DataCapture ポリシーが参照する DataCollector を事前登録
# ============================================================
resource "google_apigee_data_collector" "user_email" {
  org_id            = "organizations/${var.org_id}"
  data_collector_id = "dc_user_email"
  description       = "IAP user email"
  type              = "STRING"
}

resource "google_apigee_data_collector" "model_action" {
  org_id            = "organizations/${var.org_id}"
  data_collector_id = "dc_model_action"
  description       = "Vertex AI model:action"
  type              = "STRING"
}

resource "google_apigee_data_collector" "target_region" {
  org_id            = "organizations/${var.org_id}"
  data_collector_id = "dc_target_region"
  description       = "Target region (global or regional)"
  type              = "STRING"
}

resource "google_apigee_data_collector" "prompt_token_count" {
  org_id            = "organizations/${var.org_id}"
  data_collector_id = "dc_prompt_token_count"
  description       = "Prompt token count"
  type              = "INTEGER"
}

resource "google_apigee_data_collector" "candidates_token_count" {
  org_id            = "organizations/${var.org_id}"
  data_collector_id = "dc_candidates_token_count"
  description       = "Candidates (output) token count"
  type              = "INTEGER"
}

resource "google_apigee_data_collector" "total_token_count" {
  org_id            = "organizations/${var.org_id}"
  data_collector_id = "dc_total_token_count"
  description       = "Total token count"
  type              = "INTEGER"
}

resource "google_apigee_api" "vertexai_proxy" {
  org_id         = var.org_id
  name           = "vertexai-proxy"
  config_bundle  = data.archive_file.proxy_bundle.output_path
  detect_md5hash = data.archive_file.proxy_bundle.output_md5

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
