locals {
  analytics_region = var.analytics_region != "" ? var.analytics_region : keys(var.instances)[0]
}

# Apigee Organization
resource "google_apigee_organization" "this" {
  project_id          = var.project_id
  analytics_region    = local.analytics_region
  authorized_network  = var.network_id
  runtime_type        = "CLOUD"
  billing_type        = var.billing_type
  disable_vpc_peering = false
  retention           = var.retention
}

# Apigee インスタンス (リージョン単位)
# /22: ランタイムプレーン用、/28: トラブルシューティング用
resource "google_apigee_instance" "this" {
  for_each           = var.instances
  name               = "apigee-${each.key}"
  location           = each.key
  org_id             = google_apigee_organization.this.id
  peering_cidr_range = "SLASH_22"
  ip_range           = each.value.support_cidr_range
}

# 環境・環境グループをループで作成
resource "google_apigee_environment" "this" {
  for_each     = { for e in var.environments : e.name => e }
  name         = each.value.name
  display_name = each.value.display_name != "" ? each.value.display_name : each.value.name
  description  = each.value.description
  org_id       = google_apigee_organization.this.id
}

resource "google_apigee_instance_attachment" "this" {
  for_each = {
    for pair in setproduct(keys(google_apigee_instance.this), keys(google_apigee_environment.this)) :
    "${pair[0]}-${pair[1]}" => {
      instance    = pair[0]
      environment = pair[1]
    }
  }
  instance_id = google_apigee_instance.this[each.value.instance].id
  environment = each.value.environment
}

resource "google_apigee_envgroup" "this" {
  for_each  = { for e in var.environments : e.name => e }
  name      = "${each.value.name}-envgroup"
  hostnames = each.value.hostnames
  org_id    = google_apigee_organization.this.id
}

resource "google_apigee_envgroup_attachment" "this" {
  for_each    = google_apigee_envgroup.this
  envgroup_id = each.value.id
  environment = each.key
}
