# ============================================================
# IAP (Identity-Aware Proxy) - プロジェクトスコープ
#
# google_iap_brand / google_iap_client は 2026-03-19 に廃止済み。
# OAuth クライアントは GCP Console で手動作成し、
# client_id / client_secret を変数で渡す。
#
# 手順:
#   1. GCP Console → APIs & Services → Credentials
#   2. OAuth 2.0 Client ID を作成 (Application type: Web application)
#   3. terraform.tfvars に iap_oauth_client_id / iap_oauth_client_secret を設定
# ============================================================

# IAP サービスアカウントのプロビジョニング
# Cloud Run + IAP の連携に必要 (gcloud beta services identity create --service=iap.googleapis.com 相当)
resource "google_project_service_identity" "iap" {
  provider = google-beta
  project  = var.project_id
  service  = "iap.googleapis.com"
}
