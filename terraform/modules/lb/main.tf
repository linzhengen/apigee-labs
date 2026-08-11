# ============================================================
# Global HTTPS Load Balancer + パスルーティング + IAP
#
# /                → リダイレクト → /ui/main/ (default_ui_redirect)
# /ui/{name}/*     → Cloud Run (Serverless NEG) + IAP
# /api/*           → Apigee X (Hybrid NEG) + IAP
# ============================================================

# グローバル静的 IP
resource "google_compute_global_address" "this" {
  name    = "${var.name}-ip"
  project = var.project_id
}

# マネージド SSL 証明書
resource "google_compute_managed_ssl_certificate" "this" {
  name    = "${var.name}-cert"
  project = var.project_id
  managed {
    domains = [var.domain]
  }
}

# ============================================================
# UI フロントエンド (Cloud Run + Serverless NEG + IAP)
# ============================================================
resource "google_compute_region_network_endpoint_group" "ui" {
  for_each = { for f in var.ui_frontends : f.name => f }

  name                  = "${var.name}-ui-${each.key}-neg"
  project               = var.project_id
  network_endpoint_type = "SERVERLESS"
  region                = var.region

  cloud_run {
    service = each.value.cloud_run_service_name
  }
}

resource "google_compute_backend_service" "ui" {
  for_each = { for f in var.ui_frontends : f.name => f }

  name                  = "${var.name}-ui-${each.key}-backend"
  project               = var.project_id
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30

  backend {
    group = google_compute_region_network_endpoint_group.ui[each.key].id
  }

  # IAP: iap_config が指定された場合に有効化
  dynamic "iap" {
    for_each = var.iap_config != null ? [var.iap_config] : []
    content {
      enabled              = true
      oauth2_client_id     = iap.value.oauth2_client_id
      oauth2_client_secret = iap.value.oauth2_client_secret
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# IAP アクセス許可 (UI Backend Service)
resource "google_iap_web_backend_service_iam_member" "ui" {
  for_each = {
    for pair in flatten([
      for f in var.ui_frontends : [
        for member in var.iap_allowed_members : {
          key    = "${f.name}-${member}"
          name   = f.name
          member = member
        }
      ]
    ]) : pair.key => pair
  }

  project             = var.project_id
  web_backend_service = google_compute_backend_service.ui[each.value.name].name
  role                = "roles/iap.httpsResourceAccessor"
  member              = each.value.member
}

# ============================================================
# Apigee バックエンド (/api/* 用) + IAP
# ============================================================
# PSC NEG: Apigee インスタンスの service_attachment 経由で接続
# ヘルスチェックは PSC 側で自動管理されるため不要
resource "google_compute_region_network_endpoint_group" "apigee" {
  count = var.apigee_config != null ? 1 : 0

  name                  = "${var.name}-apigee-psc-neg"
  project               = var.project_id
  region                = var.region
  network_endpoint_type = "PRIVATE_SERVICE_CONNECT"
  psc_target_service    = var.apigee_config.service_attachment

  network    = var.apigee_config.network_self_link
  subnetwork = var.apigee_config.psc_subnetwork
}

resource "google_compute_backend_service" "apigee" {
  count = var.apigee_config != null ? 1 : 0

  name                  = "${var.name}-apigee-backend"
  project               = var.project_id
  protocol              = "HTTPS"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 60

  backend {
    group = google_compute_region_network_endpoint_group.apigee[0].id
  }

  # IAP: iap_config が指定された場合に有効化
  dynamic "iap" {
    for_each = var.iap_config != null ? [var.iap_config] : []
    content {
      enabled              = true
      oauth2_client_id     = iap.value.oauth2_client_id
      oauth2_client_secret = iap.value.oauth2_client_secret
    }
  }

  log_config {
    enable      = true
    sample_rate = 1.0
  }
}

# IAP アクセス許可 (Apigee Backend Service)
resource "google_iap_web_backend_service_iam_member" "apigee" {
  for_each = var.apigee_config != null ? toset(var.iap_allowed_members) : toset([])

  project             = var.project_id
  web_backend_service = google_compute_backend_service.apigee[0].name
  role                = "roles/iap.httpsResourceAccessor"
  member              = each.value
}

# ============================================================
# URL マップ
# ============================================================
resource "google_compute_url_map" "https" {
  name    = "${var.name}-url-map"
  project = var.project_id

  # / へのアクセスをリダイレクト
  default_url_redirect {
    path_redirect          = var.default_ui_redirect
    redirect_response_code = "FOUND"
    strip_query            = false
  }

  host_rule {
    hosts        = [var.domain]
    path_matcher = "main"
  }

  path_matcher {
    name = "main"

    # マッチしないパスはリダイレクト
    default_url_redirect {
      path_redirect          = var.default_ui_redirect
      redirect_response_code = "FOUND"
      strip_query            = false
    }

    # /api/* → Apigee
    dynamic "path_rule" {
      for_each = var.apigee_config != null ? [1] : []
      content {
        paths   = ["/api", "/api/*"]
        service = google_compute_backend_service.apigee[0].id
      }
    }

    # /ui/{name}/* → Cloud Run Backend Service
    dynamic "path_rule" {
      for_each = { for f in var.ui_frontends : f.name => f }
      content {
        paths   = ["/ui/${path_rule.key}", "/ui/${path_rule.key}/*"]
        service = google_compute_backend_service.ui[path_rule.key].id
      }
    }
  }
}

# URL マップ (HTTP → HTTPS リダイレクト)
resource "google_compute_url_map" "http_redirect" {
  name    = "${var.name}-http-redirect"
  project = var.project_id

  default_url_redirect {
    https_redirect         = true
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
    strip_query            = false
  }
}

# ============================================================
# プロキシ・フォワーディングルール
# ============================================================
resource "google_compute_target_https_proxy" "this" {
  name             = "${var.name}-https-proxy"
  project          = var.project_id
  url_map          = google_compute_url_map.https.id
  ssl_certificates = [google_compute_managed_ssl_certificate.this.id]
}

resource "google_compute_target_http_proxy" "this" {
  name    = "${var.name}-http-proxy"
  project = var.project_id
  url_map = google_compute_url_map.http_redirect.id
}

resource "google_compute_global_forwarding_rule" "https" {
  name                  = "${var.name}-https"
  project               = var.project_id
  target                = google_compute_target_https_proxy.this.id
  port_range            = "443"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.this.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name}-http"
  project               = var.project_id
  target                = google_compute_target_http_proxy.this.id
  port_range            = "80"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  ip_address            = google_compute_global_address.this.id
}
