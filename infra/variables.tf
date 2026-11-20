variable "region" {
  description = "华为云区域"
  type        = string
  default     = "cn-north-4"
}

variable "app_name" {
  description = "应用前缀；所有资源名称均由该前缀派生"
  type        = string
  default     = "rsw"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.app_name))
    error_message = "app_name 必须以小写字母开头，仅含小写字母、数字、连字符，长度为 2~15。"
  }
}

variable "apig_instance_id" {
  description = "APIG 专享实例 ID；实例由外部统一创建，本配置只引用不创建"
  type        = string
  default     = ""
}

variable "environment_name" {
  description = "APIG 发布环境名称（仅自建环境时生效）；调用该环境的 API 需携带 X-Stage 请求头"
  type        = string
  default     = "prod"
}

variable "shared_apig_env_id" {
  description = "已有共享 APIG 环境 ID；非空时不创建环境，直接使用该环境（独享实例上同名环境只能存在一个）"
  type        = string
  default     = ""
}
