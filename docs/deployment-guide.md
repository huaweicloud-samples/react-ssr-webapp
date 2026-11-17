# 部署指南

本文给出从零到可验证部署的完整命令，每一步都附预期输出。
命令默认在本仓库根目录执行，需要进入子目录时会显式写出 `cd`。

架构与设计取舍见 [architecture.md](architecture.md)。

## 0. 约定与占位符

| 占位符 | 含义 | 取值方式 |
|-|-|-|
| `<HW_ACCESS_KEY>` | Access Key ID | 控制台「我的凭证」页面的访问密钥区域 |
| `<HW_SECRET_KEY>` | Secret Access Key | 同上；两者只填入当前 shell，不要写入代码或提交到仓库 |
| `<APIG 专享实例 ID>` | 已就绪的网关实例 | 网关控制台的实例列表 |

## 1. 自检本地工具

```bash
python --version
node --version
terraform version
```

预期输出（版本不低于下表要求即可）：

```text
Python 3.11.9
v20.11.0
Terraform v1.9.8
```

要求：Terraform CLI `>= 1.5`，huaweicloud Provider `~> 1.95`，
Node.js 18 及以上（用于前端构建），Python 3.9 及以上（用于构建脚本）。

## 2. 构建前端与服务端部署包

```bash
python src/scripts/build.py
```

构建分四步，输出依次为：

```text
[build] $ npm install --no-audit --no-fund
[build] $ npm run build
[build] assets manifest -> .../src/frontend/src/build-assets.json: {"js": ["static/js/main.<哈希>.js"], "css": []}
[build] server bundle size: 87121 bytes
[build] zip -> .../src/dist/functions/ssr-render.zip (27995 bytes)
[build] done
```

说明：

- 首次构建会安装前端依赖，耗时较长；后续构建复用已安装的依赖。
- 客户端构建产物输出到 `src/dist/frontend-build/`，按内容哈希命名。
- 服务端 bundle 打包为确定性 ZIP（固定条目时间戳），同一份源码重复构建摘要一致。
- `src/frontend/src/build-assets.json` 记录哈希后的资源名，供服务端渲染引用。

## 3. 本地渲染冒烟

```bash
node src/test/smoke_ssr.js
```

脚本在本地构造事件并调用渲染入口，校验输出的 HTML 含根节点与 hydration 数据，
不访问任何云端接口。

## 4. 静态校验

```bash
cd infra
terraform init
terraform validate
```

预期输出：

```text
Success! The configuration is valid, but there were some
validation warnings as shown above.
```

未使用官方插件镜像时，警告内容是本地开发覆盖的提示，属预期输出。

## 5. 配置访问凭据

```bash
export HW_ACCESS_KEY=<HW_ACCESS_KEY>
export HW_SECRET_KEY=<HW_SECRET_KEY>
```

## 6. 提供部署参数

必填项一个：`apig_instance_id`。

```bash
export TF_VAR_apig_instance_id="<APIG 专享实例 ID>"
```

### 6.1 主要参数

| 变量 | 类型 | 默认值 | 必填 | 说明 |
|-|-|-|-|-|
| `region` | string | `cn-north-4` | 否 | 部署区域 |
| `app_name` | string | `rsw` | 否 | 资源名称前缀；小写字母开头，可含数字与连字符，长度 2~15 |
| `apig_instance_id` | string | 空 | 是 | 网关专享实例 ID |
| `environment_name` | string | `prod` | 否 | 发布环境名（仅自建环境时生效） |
| `shared_apig_env_id` | string | 空 | 否 | 已有共享环境 ID；非空时不创建环境 |

### 6.2 几处容易填错的位置

- `app_name` 会进入桶名与对象键，长度上限 15，只能小写。
- 给出 `shared_apig_env_id` 时不再创建环境，`environment_name` 不再生效。
- 桶名为「前缀 + 随机后缀」，部署后以 `terraform output static_bucket` 为准。

## 7. 创建资源

```bash
cd infra
terraform plan -out=rsw.tfplan
terraform apply rsw.tfplan
```

`terraform plan` 预期会创建以下资源：

```text
Plan: 15 to add, 0 to change, 0 to destroy.
```

构成：1 个日志组与 2 条日志流、1 个自定义策略与 1 个委托、2 个函数、
1 个对象存储桶、随构建产物数量变化的对象上传、1 个分组与 1 个环境（共享环境时为 0）、
3 条 API、3 条发布记录。

对象上传的数量等于 `src/dist/frontend-build/` 下的文件数（排除 `index.html`），
因此 `Plan` 的数量会随前端产物浮动，以上数字不含对象上传。

`terraform apply` 完成后预期输出：

```text
Apply complete! Resources: N added, 0 changed, 0 destroyed.
```

## 8. 读取部署输出

```bash
terraform output
```

预期列出以下输出名：

```text
api_function_urn     api_products_url     apig_env_id
apig_env_name        apig_instance_id     log_group_id
log_stream_ids       page_base_url        region
ssr_function_urn     ssr_page_url         static_base_url
static_bucket
```

常用取值：

```bash
terraform output ssr_page_url      # 页面入口
terraform output api_products_url  # 商品接口地址
terraform output static_base_url   # 静态资产前缀
terraform output static_bucket     # 静态资产桶名
```

## 9. 验证部署

```bash
python src/scripts/verify_e2e.py
```

脚本读取部署输出并对真实网关地址做六项校验，结果写入 `verify-result.json`。
预期输出：

```json
{"passed": true, "checks": 6}
```

六项覆盖：首屏返回 `text/html`、页面引用的资产地址指向对象存储桶、
`/ssr/{proxy}` 路由可用、商品接口返回五条记录、静态资产直链可访问、
缺少 `X-Stage` 时返回 404。

## 10. 手工验证示例

```bash
export BASE="$(terraform output -raw page_base_url)"
export ASSETS="$(terraform output -raw static_base_url)"
```

取首屏页面：

```bash
curl -s "$BASE/" -H "X-Stage: prod" | head -20
```

预期返回 HTML，包含根节点占位与 hydration 数据脚本：

```html
<div id="root">…</div>
<script>window.__INITIAL_DATA__ = {…}</script>
```

页面中引用的脚本与样式均指向静态资产前缀：

```bash
curl -s "$BASE/" -H "X-Stage: prod" | grep -o "$ASSETS[^\"]*" | head -3
```

预期输出形如：

```text
https://<桶名>.obs.<区域>.myhuaweicloud.com/static/js/main.<哈希>.js
```

直接访问该资产：

```bash
curl -sI "$ASSETS/static/js/main.<哈希>.js" | head -3
```

预期返回 200。

商品接口：

```bash
curl -s "$BASE/api/products" -H "X-Stage: prod" | head -c 200
```

预期返回商品数组，共 5 条记录。

### 10.1 验证服务端渲染确实生效

关闭浏览器脚本后再取一次页面，或用脚本检查首屏是否已含商品内容：

```bash
curl -s "$BASE/" -H "X-Stage: prod" | grep -o "示例商品名" | head -3
```

预期能直接在 HTML 中看到商品内容——这说明首屏在服务端已渲染完成，
而不是等客户端 JavaScript 执行后才出现。

**部署完成后请按本节步骤在真实环境自行验证，确认功能可用后方可视为交付完成。**

## 11. 更新页面或资产

```bash
python src/scripts/build.py
cd infra
terraform apply
```

预期行为：渲染函数因部署包变化而更新；对象存储桶按新产物增删对象；
数据函数代码未变时不重建。

## 12. 释放资源

```bash
cd infra
terraform destroy
```

预期输出：

```text
Destroy complete! Resources: N destroyed.
```

销毁会删除两个函数、分组/环境/API/发布、日志组与日志流、委托与自定义策略，
以及对象存储桶与桶内全部对象。网关专享实例属外部资源，不在本目录的清理范围。

## 13. 故障排查

| 现象 | 定位方向 |
|-|-|
| 函数报「找不到入口」 | 渲染函数的 ZIP 根目录必须有 `index.js`；入口为 `index.handler` |
| 页面返回 404 | 是否遗漏 `X-Stage` 请求头；三条路由是否都已发布到目标环境 |
| 页面白屏但状态码 200 | 检查 HTML 是否含根节点与 hydration 数据；渲染函数日志中的取数步骤是否成功 |
| 资产 404 | 对象是否已上传到 `static_bucket`；`static_base_url` 是否与实际桶域名一致 |
| 渲染函数报取数失败 | 委托是否绑定自定义策略；策略资源路径是否与数据函数名完全一致 |
| 首次请求较慢 | 函数冷启动所致，重试即可；持续偏慢检查渲染函数内存与超时 |
| 日志为空 | 两个函数必须同时绑定日志组 ID/名称与日志流 ID/名称四个参数 |
