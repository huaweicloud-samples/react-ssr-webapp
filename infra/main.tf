data "huaweicloud_account" "current" {}

resource "random_string" "bucket_suffix" {
  length  = 8
  special = false
  upper   = false
}

locals {
  # The SSR function calls the products API function through the FunctionGraph
  # synchronous invocation endpoint and renders static asset URLs from the
  # object storage bucket domain.
  static_base_url = "https://${huaweicloud_obs_bucket.static.bucket}.obs.${var.region}.myhuaweicloud.com"

  ssr_function_env = {
    REGION           = var.region
    PROJECT_ID       = data.huaweicloud_account.current.current_project_id
    API_FUNCTION_URN = trimsuffix(huaweicloud_fgs_function.api.urn, ":latest")
    STATIC_BASE_URL  = local.static_base_url
  }

  api_routes = {
    ssr_index = {
      method   = "ANY"
      path     = "/"
      function = "ssr"
    }
    ssr_proxy = {
      method   = "ANY"
      path     = "/ssr/{proxy}"
      function = "ssr"
    }
    api_proxy = {
      method   = "ANY"
      path     = "/api/{proxy}"
      function = "api"
    }
  }

  route_function_urns = {
    ssr = trimsuffix(huaweicloud_fgs_function.ssr_render.urn, ":latest")
    api = trimsuffix(huaweicloud_fgs_function.api.urn, ":latest")
  }

  content_types = {
    js          = "application/javascript"
    css         = "text/css"
    json        = "application/json"
    png         = "image/png"
    ico         = "image/x-icon"
    svg         = "image/svg+xml"
    txt         = "text/plain"
    html        = "text/html"
    webmanifest = "application/manifest+json"
  }

  # Everything from the frontend build output except the client shell page,
  # which the ssr-render function generates instead.
  static_files = {
    for path in fileset("${path.module}/../src/dist/frontend-build", "**/*") :
    path => path if path != "index.html"
  }

  # APIG environment: a dedicated instance allows only one environment per
  # name. When a shared environment ID is provided it is reused as-is;
  # otherwise this module creates its own. Every resource referencing the
  # environment uses local.apig_env_id / local.apig_env_name.
  use_shared_apig_env = var.shared_apig_env_id != ""
  apig_env_id         = local.use_shared_apig_env ? var.shared_apig_env_id : huaweicloud_apig_environment.rsw[0].id
}

# ---------------------------------------------------------------------------
# Logs
# ---------------------------------------------------------------------------

resource "huaweicloud_lts_group" "rsw" {
  group_name  = "${var.app_name}-logs"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "ssr_render" {
  group_id    = huaweicloud_lts_group.rsw.id
  stream_name = "${var.app_name}-ssr-render"
}

resource "huaweicloud_lts_stream" "api" {
  group_id    = huaweicloud_lts_group.rsw.id
  stream_name = "${var.app_name}-api"
}

# ---------------------------------------------------------------------------
# Functions
# ---------------------------------------------------------------------------

resource "huaweicloud_identity_role" "invoke_api" {
  name        = "${var.app_name}-invoke-api"
  description = "Allow the SSR render function to invoke the products API function"
  type        = "XA"

  policy = jsonencode({
    Version = "1.1"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["FunctionGraph:function:invoke"]
        Resource = ["FunctionGraph:*:*:function:default/${var.app_name}-api"]
      }
    ]
  })
}

resource "huaweicloud_identity_agency" "ssr_invoke" {
  name                  = "${var.app_name}-ssr-invoke"
  description           = "Agency for the ${var.app_name} SSR render function"
  delegated_domain_name = "op_svc_cff"
  duration              = "FOREVER"

  project_role {
    project = var.region
    roles   = [huaweicloud_identity_role.invoke_api.name]
  }

  lifecycle {
    ignore_changes = [delegated_service_name]
  }
}

resource "huaweicloud_fgs_function" "api" {
  name           = "${var.app_name}-api"
  app            = "default"
  handler        = "index.handler"
  runtime        = "Node.js18.15"
  memory_size    = 128
  timeout        = 15
  code_type      = "inline"
  func_code      = base64encode(file("${path.module}/../src/functions/api/index.js"))
  enable_lts_log = true

  log_group_id    = huaweicloud_lts_group.rsw.id
  log_group_name  = huaweicloud_lts_group.rsw.group_name
  log_stream_id   = huaweicloud_lts_stream.api.id
  log_stream_name = huaweicloud_lts_stream.api.stream_name
}

resource "huaweicloud_fgs_function" "ssr_render" {
  name           = "${var.app_name}-ssr-render"
  app            = "default"
  handler        = "index.handler"
  runtime        = "Node.js18.15"
  memory_size    = 128
  timeout        = 15
  code_type      = "zip"
  func_code      = filebase64("${path.module}/../src/dist/functions/ssr-render.zip")
  agency         = huaweicloud_identity_agency.ssr_invoke.name
  user_data      = jsonencode(local.ssr_function_env)
  enable_lts_log = true

  log_group_id    = huaweicloud_lts_group.rsw.id
  log_group_name  = huaweicloud_lts_group.rsw.group_name
  log_stream_id   = huaweicloud_lts_stream.ssr_render.id
  log_stream_name = huaweicloud_lts_stream.ssr_render.stream_name
}

# ---------------------------------------------------------------------------
# Static assets (object storage, public read)
# ---------------------------------------------------------------------------

resource "huaweicloud_obs_bucket" "static" {
  bucket = "${var.app_name}-static-${random_string.bucket_suffix.result}"
  acl    = "public-read"
}

resource "huaweicloud_obs_bucket_object" "static" {
  for_each = local.static_files

  bucket       = huaweicloud_obs_bucket.static.bucket
  key          = each.key
  source       = "${path.module}/../src/dist/frontend-build/${each.key}"
  content_type = lookup(local.content_types, try(reverse(split(".", each.key))[0], ""), "application/octet-stream")
  acl          = "public-read"
}

# ---------------------------------------------------------------------------
# APIG: group, environment, APIs, publications
# ---------------------------------------------------------------------------

resource "huaweicloud_apig_group" "rsw" {
  instance_id           = var.apig_instance_id
  name                  = "${var.app_name}-group"
  description           = "React SSR webapp group"
  domain_access_enabled = true
}

resource "huaweicloud_apig_environment" "rsw" {
  count = local.use_shared_apig_env ? 0 : 1

  instance_id = var.apig_instance_id
  name        = var.environment_name
  description = "React SSR webapp validation environment"
}

# When reusing a shared environment, resolve its name (X-Stage value) by ID;
# a non-existent ID fails during plan.
data "huaweicloud_apig_environments" "rsw" {
  count       = local.use_shared_apig_env ? 1 : 0
  instance_id = var.apig_instance_id
}

locals {
  shared_apig_env_matches = [
    for env in flatten(data.huaweicloud_apig_environments.rsw[*].environments) :
    env if env.id == var.shared_apig_env_id
  ]
  apig_env_name = local.use_shared_apig_env ? local.shared_apig_env_matches[0].name : huaweicloud_apig_environment.rsw[0].name
}

resource "huaweicloud_apig_api" "rsw" {
  for_each = local.api_routes

  instance_id             = var.apig_instance_id
  group_id                = huaweicloud_apig_group.rsw.id
  type                    = "Public"
  name                    = "${var.app_name}-${each.key}"
  request_protocol        = "HTTPS"
  request_method          = each.value.method
  request_path            = each.value.path
  security_authentication = "NONE"
  matching                = "Exact"

  func_graph {
    function_urn     = local.route_function_urns[each.value.function]
    version          = "latest"
    network_type     = "V1"
    request_protocol = "HTTPS"
    timeout          = 15000
    invocation_type  = "sync"
  }
}

resource "huaweicloud_apig_api_publishment" "rsw" {
  for_each = local.api_routes

  instance_id = var.apig_instance_id
  env_id      = local.apig_env_id
  api_id      = huaweicloud_apig_api.rsw[each.key].id
  description = "Published by ${var.app_name}"
}
