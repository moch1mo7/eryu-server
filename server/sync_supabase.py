#!/usr/bin/env python3
"""Supabase 存档同步 — 启动时恢复，每10分钟备份，退出时保存。
由 start.sh 在后台调用，独立于 eryu 主进程。
"""
import json, os, sys, time, urllib.request, urllib.error

DATA_DIR = "/app/data"
APP_DIR = "/app"
BASE_URL = os.environ.get("SUPABASE_URL", "")
BUCKET = os.environ.get("SUPABASE_BUCKET", "eryu-data")
KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")

# 若 KEY 未设置，尝试从内置 base64 解码
if not KEY:
    try:
        import base64
        KEY = base64.b64decode(
            "c2Jfc2VjcmV0X2x5QkZEMVhxQkRiQy03UkFtay15VXdfclJXRExWV1I="
        ).decode()
        print("[sync] KEY decoded from built-in base64")
    except Exception:
        pass

if not BASE_URL or not KEY:
    print("[sync] Supabase not configured — skipping sync")
    sys.exit(0)

HEADERS = {
    "Authorization": f"Bearer {KEY}",
    "apikey": KEY,
}

def supabase_url(filename, in_app=False):
    """返回 Supabase Storage 对象 URL"""
    base = f"{BASE_URL}/storage/v1/object/{BUCKET}"
    return f"{base}/{filename}"

def download(filename, dest_dir):
    """从 Supabase 下载文件，仅在 HTTP 200 时覆盖目标"""
    url = supabase_url(filename)
    dest = os.path.join(dest_dir, filename)
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = resp.read()
            # 写临时文件，成功再 rename
            tmp = dest + ".tmp"
            with open(tmp, "wb") as f:
                f.write(data)
            os.replace(tmp, dest)
            print(f"[sync] DOWNLOADED {filename} ({len(data)} bytes)")
            return True
    except urllib.error.HTTPError as e:
        if e.code == 404:
            pass  # 正常：首次使用，桶里还没有文件
        else:
            print(f"[sync] DOWNLOAD {filename}: HTTP {e.code}")
    except Exception as e:
        print(f"[sync] DOWNLOAD {filename}: {e}")
    return False

def upload(filename, src_dir):
    """上传文件到 Supabase"""
    src = os.path.join(src_dir, filename)
    if not os.path.isfile(src):
        return
    url = supabase_url(filename)
    try:
        with open(src, "rb") as f:
            data = f.read()
        req = urllib.request.Request(url, data=data, method="POST",
            headers={**HEADERS, "Content-Type": "application/octet-stream",
                     "x-upsert": "true"})
        with urllib.request.urlopen(req, timeout=15):
            print(f"[sync] UPLOADED {filename}")
    except Exception as e:
        print(f"[sync] UPLOAD {filename}: {e}")

# ══════════════════════════
# 启动时：从 Supabase 恢复
# ══════════════════════════
print("[sync] Starting restore from Supabase...")

# 凭证文件（放在 /app/）
for f in [".netease_cred", ".secret"]:
    download(f, APP_DIR)

# 数据文件（放在 /app/data/）
for f in ["music_data.json", "music_memory.json", "music_playlist.json", "music_remote.json"]:
    download(f, DATA_DIR)

# ══════════════════════════
# 后台循环：每10分钟上传
# ══════════════════════════
print("[sync] Restore complete. Starting background backup loop (every 10min)...")

try:
    while True:
        time.sleep(600)  # 10 分钟
        # 数据文件
        for f in ["music_data.json", "music_memory.json", "music_playlist.json", "music_remote.json"]:
            upload(f, DATA_DIR)
        # 凭证文件
        for f in [".netease_cred", ".secret"]:
            upload(f, APP_DIR)
except KeyboardInterrupt:
    pass
finally:
    # ══════════════════════════
    # 退出时：最后一次上传
    # ══════════════════════════
    print("[sync] Exit — final upload...")
    for f in ["music_data.json", "music_memory.json", "music_playlist.json", "music_remote.json"]:
        upload(f, DATA_DIR)
    for f in [".netease_cred", ".secret"]:
        upload(f, APP_DIR)
    print("[sync] Done.")
