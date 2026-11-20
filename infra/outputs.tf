data "huaweicloud_apig_groups" "rsw" {
  instance_id = var.apig_instance_id
  group_id    = huaweicloud_apig_group.rsw.id
}

output "region" {
  description = "部署区域"
  value       = var.region
}

output "apig_instance_id" {
  description = "APIG 专享实例 ID"
  value       = var.apig_instance_id
}

output "apig_env_id" {
  description = "APIG 环境 ID（共享环境时取传入的 shared_apig_env_id）"
  value       = local.apig_env_id
}

output "apig_env_name" {
  description = "APIG 环境名称（调用时需携带 X-Stage 请求头）"
  value       = local.apig_env_name
}

output "page_base_url" {
  description = "页面访问基地址（分组调试子域名）"
  value       = "https://${data.huaweicloud_apig_groups.rsw.groups[0].sl_domain}"
}

output "ssr_page_url" {
  description = "SSR 页面入口（'/' 与 '/ssr/{proxy}' 均由渲染函数生成）"
  value       = "https://${data.huaweicloud_apig_groups.rsw.groups[0].sl_domain}/"
}

output "api_products_url" {
  description = "产品数据接口地址"
  value       = "https://${data.huaweicloud_apig_groups.rsw.groups[0].sl_domain}/api/products"
}

output "static_base_url" {
  description = "静态资产对象存储访问前缀"
  value       = local.static_base_url
}

output "static_bucket" {
  description = "静态资产桶名"
  value       = huaweicloud_obs_bucket.static.bucket
}

output "ssr_function_urn" {
  description = "SSR 渲染函数 URN"
  value       = huaweicloud_fgs_function.ssr_render.urn
}

output "api_function_urn" {
  description = "产品数据 API 函数 URN"
  value       = huaweicloud_fgs_function.api.urn
}

output "log_group_id" {
  description = "LTS 日志组 ID"
  value       = huaweicloud_lts_group.rsw.id
}

output "log_stream_ids" {
  description = "LTS 日志流 ID（按函数）"
  value = {
    ssr_render = huaweicloud_lts_stream.ssr_render.id
    api        = huaweicloud_lts_stream.api.id
  }
}
