# ============================================================
# IAP (Identity-Aware Proxy) - プロジェクトスコープ
#
# google_iap_brand はプロジェクトに 1 つしか作成できないため、
# LB モジュールとは独立して管理する。
# ============================================================

resource "google_iap_brand" "this" {
  project           = var.project_id
  support_email     = var.support_email
  application_title = var.application_title
}

resource "google_iap_client" "this" {
  display_name = var.display_name
  brand        = google_iap_brand.this.name
}
