#!/usr/bin/env python3
"""Build the React frontend, the SSR function bundle and deterministic zips.

Steps:
1. npm install (if node_modules missing) / react-scripts build (CRA output -> dist/frontend-build)
2. Scan the CRA build output and write frontend/src/build-assets.json (hashed js/css names)
3. webpack server bundle (dist/server-build/index.js)
4. Deterministic zip of the server bundle -> dist/functions/ssr-render.zip
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FRONTEND = ROOT / "src" / "frontend"
DIST = ROOT / "src" / "dist"
FRONTEND_BUILD = DIST / "frontend-build"
SERVER_BUILD = DIST / "server-build"
FUNCTIONS_DIST = DIST / "functions"

FIXED_DATE = (2024, 1, 1, 0, 0, 0)


def run(cmd: list[str], env: dict, cwd: Path) -> None:
    print(f"[build] $ {' '.join(cmd)}", flush=True)
    # shell=True on Windows so that npm.cmd is resolved through PATHEXT.
    result = subprocess.run(cmd, cwd=str(cwd), env=env, shell=(os.name == "nt"))
    if result.returncode != 0:
        raise SystemExit(f"[build] command failed: {' '.join(cmd)}")


def npm_env() -> dict:
    env = dict(os.environ)
    env["CI"] = "false"
    env["GENERATE_SOURCEMAP"] = "false"
    env.setdefault("NODE_OPTIONS", "--max-old-space-size=2048")
    return env


def build_cra(env: dict) -> None:
    if not (FRONTEND / "node_modules").is_dir():
        run(["npm", "install", "--no-audit", "--no-fund"], env, FRONTEND)
    shutil.rmtree(FRONTEND / "build", ignore_errors=True)
    run(["npm", "run", "build"], env, FRONTEND)
    shutil.rmtree(FRONTEND_BUILD, ignore_errors=True)
    shutil.copytree(FRONTEND / "build", FRONTEND_BUILD)


def write_assets_manifest() -> dict:
    js_files = sorted(
        p.relative_to(FRONTEND_BUILD).as_posix()
        for p in (FRONTEND_BUILD / "static" / "js").glob("*.js")
        if not p.name.endswith((".LICENSE.txt", ".map"))
    )
    css_files = sorted(
        p.relative_to(FRONTEND_BUILD).as_posix()
        for p in (FRONTEND_BUILD / "static" / "css").glob("*.css")
        if not p.name.endswith(".map")
    )
    manifest = {"js": js_files, "css": css_files}
    target = FRONTEND / "src" / "build-assets.json"
    target.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"[build] assets manifest -> {target}: {manifest}", flush=True)
    return manifest


def build_server_bundle(env: dict) -> None:
    shutil.rmtree(SERVER_BUILD, ignore_errors=True)
    run(["npm", "run", "build-server"], env, FRONTEND)
    bundle = SERVER_BUILD / "index.js"
    if not bundle.is_file():
        raise SystemExit("[build] server bundle missing after webpack build")
    print(f"[build] server bundle size: {bundle.stat().st_size} bytes", flush=True)


def pack_zip_deterministic(zip_path: Path, entries: dict[str, Path]) -> None:
    """entries: arcname -> source file; fixed timestamps.

    注意：不要设置 external_attr 的 0x10 位（DOS 目录标志），FunctionGraph
    解包时会将带该位的条目当作目录处理，运行时报 not found module。
    """
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for arcname in sorted(entries):
            info = zipfile.ZipInfo(arcname, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, entries[arcname].read_bytes())
    print(f"[build] zip -> {zip_path} ({zip_path.stat().st_size} bytes)", flush=True)


def main() -> int:
    env = npm_env()
    npm_only = "--npm" in sys.argv
    if not npm_only:
        build_cra(env)
    manifest = write_assets_manifest() if FRONTEND_BUILD.is_dir() else None
    if manifest is None:
        raise SystemExit("[build] frontend build output missing")
    build_server_bundle(env)
    pack_zip_deterministic(
        FUNCTIONS_DIST / "ssr-render.zip",
        {"index.js": SERVER_BUILD / "index.js"},
    )
    print("[build] done", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
