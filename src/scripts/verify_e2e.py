#!/usr/bin/env python3
"""Post-apply end-to-end verification for the React SSR webapp.

Reads terraform outputs, then checks over the deployed APIG routes:
1. GET /            -> 200 text/html with server-rendered markup (not an empty shell)
2. GET /ssr/{proxy} -> 200 text/html served by the same render function
3. GET /api/products-> 200 JSON product list
4. static asset URLs embedded in the HTML resolve with 200 over object storage
All APIG calls carry the X-Stage header of the published environment.
Writes verify-result.json next to this script's parent directory.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TERRAFORM_EXE = "C:/Users/Administrator/AppData/Local/Temp/terraform.exe"
# Bypass any system proxy configuration for direct cloud access.
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def load_outputs() -> dict:
    exe = TERRAFORM_EXE if Path(TERRAFORM_EXE).exists() else "terraform"
    raw = subprocess.run(
        [exe, "output", "-json"], cwd=str(ROOT / "infra"), capture_output=True, check=True
    ).stdout
    return {key: item["value"] for key, item in json.loads(raw.decode("utf-8")).items()}


def http_get(url: str, stage: str | None = None, timeout: int = 30) -> tuple[int, dict, bytes]:
    headers = {"User-Agent": "rsw-verify/1.0"}
    if stage:
        headers["X-Stage"] = stage
    request = urllib.request.Request(url, headers=headers, method="GET")
    try:
        with OPENER.open(request, timeout=timeout) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read()


def http_get_retry(url: str, stage: str | None = None, attempts: int = 6, delay: float = 10.0):
    last_error = None
    for _ in range(attempts):
        try:
            return http_get(url, stage)
        except urllib.error.URLError as error:
            last_error = error
            time.sleep(delay)
    raise RuntimeError(f"GET {url} failed after {attempts} attempts: {last_error}")


def main() -> int:
    outputs = load_outputs()
    base = outputs["page_base_url"].rstrip("/")
    stage = outputs.get("apig_env_name", "prod")
    static_base = outputs["static_base_url"].rstrip("/")
    checks: list[dict] = []

    def record(name: str, passed: bool, detail: dict) -> None:
        checks.append({"name": name, "passed": passed, **detail})
        print(f"[verify] {'PASS' if passed else 'FAIL'} {name}: {json.dumps(detail, ensure_ascii=False)[:300]}")
        if not passed:
            raise AssertionError(f"check failed: {name}")

    # 1. SSR index page.
    status, headers, body = http_get_retry(f"{base}/", stage)
    html = body.decode("utf-8", "replace")
    content_type = headers.get("Content-Type", headers.get("content-type", ""))
    record(
        "ssr_index_page",
        status == 200
        and "text/html" in content_type
        and "Rendered on Server" in html
        and "item 1" in html
        and "product 5 description" in html
        and "<div id=\"root\"></div>" not in html,
        {"status": status, "content_type": content_type, "bytes": len(body)},
    )

    # 2. Asset URLs in the HTML must point at the object storage prefix.
    asset_urls = re.findall(r'(?:src|href)="(https://[^"]+\.(?:js|css))"', html)
    record(
        "asset_urls_use_object_storage",
        len(asset_urls) >= 1 and all(url.startswith(static_base) for url in asset_urls),
        {"asset_urls": asset_urls[:5]},
    )

    # 3. SSR proxy route.
    status, headers, body = http_get_retry(f"{base}/ssr/home", stage)
    html2 = body.decode("utf-8", "replace")
    record(
        "ssr_proxy_route",
        status == 200 and "Rendered on Server" in html2 and "item 1" in html2,
        {"status": status, "bytes": len(body)},
    )

    # 4. Products API.
    status, headers, body = http_get_retry(f"{base}/api/products", stage)
    products = json.loads(body.decode("utf-8", "replace")) if status == 200 else []
    record(
        "products_api",
        status == 200
        and isinstance(products, list)
        and len(products) == 5
        and products[0].get("name") == "item 1",
        {"status": status, "count": len(products) if isinstance(products, list) else 0},
    )

    # 5. Static asset direct link (object storage, no X-Stage needed).
    asset_status, asset_headers, asset_body = http_get_retry(asset_urls[0])
    record(
        "static_asset_direct_link",
        asset_status == 200 and len(asset_body) > 0,
        {"url": asset_urls[0], "status": asset_status, "bytes": len(asset_body)},
    )

    # 6. Negative probe: without X-Stage the non-RELEASE route is not served.
    status_no_stage, _, _ = http_get(f"{base}/api/products")
    record(
        "stage_header_required",
        status_no_stage != 200,
        {"status_without_stage": status_no_stage},
    )

    result = {
        "passed": all(item["passed"] for item in checks),
        "mode": "apig",
        "base_url": base,
        "stage": stage,
        "static_base_url": static_base,
        "checks": checks,
    }
    out = ROOT / "verify-result.json"
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps({"passed": result["passed"], "checks": len(checks)}, ensure_ascii=False))
    return 0 if result["passed"] else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except AssertionError as error:
        result = {"passed": False, "error": str(error)}
        (ROOT / "verify-result.json").write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        print(str(error))
        raise SystemExit(1)
