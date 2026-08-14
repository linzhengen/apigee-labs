# ============================================================
# 利用ログ非同期パイプライン
#
#   Apigee (ServiceCallout)
#     → Pub/Sub トピック
#       → Cloud Run Functions (Eventarc トリガー)
#         → BigQuery
#
# Apigee 側は fire-and-forget で送信するため、レスポンスタイムに
# 影響を与えずにメッセージ・トークン利用量を記録できる。
# ============================================================

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }
  }
}

# ============================================================
# Pub/Sub トピック
# ============================================================
resource "google_pubsub_topic" "usage_logs" {
  project                    = var.project_id
  name                       = var.topic_name
  message_retention_duration = var.message_retention_duration
}

# Apigee プロキシ SA など、トピックへ publish する権限
resource "google_pubsub_topic_iam_member" "publishers" {
  for_each = toset(var.publisher_members)

  project = var.project_id
  topic   = google_pubsub_topic.usage_logs.name
  role    = "roles/pubsub.publisher"
  member  = each.value
}

# ============================================================
# BigQuery (書き込み先)
# ============================================================
resource "google_bigquery_dataset" "usage" {
  project                    = var.project_id
  dataset_id                 = var.dataset_id
  friendly_name              = "Apigee usage logs"
  description                = "Apigee 経由の Vertex AI 利用ログ (メッセージ・トークン数)"
  location                   = var.bigquery_location
  delete_contents_on_destroy = var.delete_contents_on_destroy
}

resource "google_bigquery_table" "usage_logs" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.usage.dataset_id
  table_id            = var.table_id
  description         = "1 リクエスト = 1 行。timestamp で日次パーティション、user_id / model でクラスタリング"
  schema              = file("${path.module}/schema.json")
  deletion_protection = false

  time_partitioning {
    type          = "DAY"
    field         = "timestamp"
    expiration_ms = var.partition_expiration_days > 0 ? var.partition_expiration_days * 24 * 60 * 60 * 1000 : null
  }

  clustering = ["user_id", "model"]
}

# ============================================================
# Cloud Run Functions 用サービスアカウント
#
# ビルド (Cloud Build) とランタイムの両方で使用する。
# ============================================================
resource "google_service_account" "usage_logger" {
  project      = var.project_id
  account_id   = "${var.function_name}-sa"
  display_name = "Usage logger function SA"
}

resource "google_project_iam_member" "usage_logger" {
  for_each = toset([
    # Eventarc からのイベント受信 + 関数の呼び出し
    "roles/eventarc.eventReceiver",
    "roles/run.invoker",
    # Cloud Build がユーザー管理 SA でビルドするために必要な権限
    "roles/logging.logWriter",
    "roles/artifactregistry.writer",
    "roles/storage.objectViewer",
  ])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.usage_logger.email}"
}

# BigQuery への書き込みはデータセット単位に限定する
resource "google_bigquery_dataset_iam_member" "usage_logger" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.usage.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.usage_logger.email}"
}

# Pub/Sub サービスエージェントを先に作成する
# (API 有効化直後は存在せず、IAM 付与が失敗するため)
resource "google_project_service_identity" "pubsub" {
  provider = google-beta
  project  = var.project_id
  service  = "pubsub.googleapis.com"
}

# Eventarc (Pub/Sub) がプッシュ時に OIDC トークンを生成するために必要
resource "google_project_iam_member" "pubsub_token_creator" {
  project = var.project_id
  role    = "roles/iam.serviceAccountTokenCreator"
  member  = "serviceAccount:${google_project_service_identity.pubsub.email}"
}

# ============================================================
# 関数ソース (GCS にアップロード)
# ============================================================
resource "google_storage_bucket" "function_source" {
  project                     = var.project_id
  name                        = "${var.project_id}-${var.function_name}-source"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type = "Delete"
    }
  }
}

data "archive_file" "function_source" {
  type        = "zip"
  source_dir  = var.function_source_dir
  output_path = "${path.module}/${var.function_name}.zip"
  excludes    = ["__pycache__", ".venv", "*.pyc"]
}

# オブジェクト名にハッシュを含め、ソース変更時に確実に再デプロイさせる
resource "google_storage_bucket_object" "function_source" {
  name   = "${var.function_name}-${data.archive_file.function_source.output_md5}.zip"
  bucket = google_storage_bucket.function_source.name
  source = data.archive_file.function_source.output_path
}

# ============================================================
# Cloud Run Functions (Pub/Sub トリガー)
# ============================================================
resource "google_cloudfunctions2_function" "usage_logger" {
  project     = var.project_id
  name        = var.function_name
  location    = var.region
  description = "Pub/Sub の Apigee 利用ログを BigQuery に記録する"

  build_config {
    runtime         = "python312"
    entry_point     = "handle_usage_log"
    service_account = google_service_account.usage_logger.id

    source {
      storage_source {
        bucket = google_storage_bucket.function_source.name
        object = google_storage_bucket_object.function_source.name
      }
    }
  }

  service_config {
    min_instance_count    = 0
    max_instance_count    = var.max_instance_count
    available_memory      = "256Mi"
    timeout_seconds       = 60
    service_account_email = google_service_account.usage_logger.email
    # Pub/Sub / Eventarc は同一プロジェクトからの呼び出しのため内部扱いになる
    ingress_settings = "ALLOW_INTERNAL_ONLY"

    environment_variables = {
      BQ_PROJECT = var.project_id
      BQ_DATASET = google_bigquery_dataset.usage.dataset_id
      BQ_TABLE   = google_bigquery_table.usage_logs.table_id
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = google_pubsub_topic.usage_logs.id
    service_account_email = google_service_account.usage_logger.email
    # BigQuery 書き込み失敗時は Pub/Sub の再配信に委ねる
    retry_policy = "RETRY_POLICY_RETRY"
  }

  depends_on = [
    google_project_iam_member.usage_logger,
    google_project_iam_member.pubsub_token_creator,
    google_bigquery_dataset_iam_member.usage_logger,
  ]
}
