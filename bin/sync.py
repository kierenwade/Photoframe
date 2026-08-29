#!/usr/bin/env python3
"""Pull photos from Google Drive, downscale them, and write a manifest.

Flow:
  1. `rclone sync`  remote -> /data/photos/originals   (read-only service account)
  2. downscale/convert new or changed files -> /data/photos/processed/*.jpg
  3. prune processed files whose original has gone
  4. write /data/photos/manifest.json  (the list the slideshow reads)

Safe to run repeatedly; step 2 is incremental via mtime.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageOps

try:  # optional HEIC/HEIF support
    import pillow_heif

    pillow_heif.register_heif_opener()
except Exception:  # noqa: BLE001 - purely optional
    pass

ROOT = Path(__file__).resolve().parent.parent


def _config_path() -> Path:
    # live config on the writable data partition (editable with Overlay FS on);
    # repo copy is the fallback for local dev
    for cand in (os.environ.get("FRAME_CONFIG"), "/data/config.toml"):
        if cand and Path(cand).is_file():
            return Path(cand)
    return ROOT / "config.toml"


CFG = tomllib.loads(_config_path().read_text())
S = CFG["sync"]

# on the Pi this is /data/photos; override for local dev with FRAME_PHOTOS_DIR
LOCAL = Path(os.environ.get("FRAME_PHOTOS_DIR", S["local_dir"]))
ORIG = LOCAL / "originals"
PROC = LOCAL / "processed"
MANIFEST = LOCAL / "manifest.json"

MAX_DIM = int(S.get("max_dimension", 3840))
QUALITY = int(S.get("jpeg_quality", 88))
RCLONE_CONFIG = S.get("rclone_config", "/data/secrets/rclone.conf")
MAX_FILE_MB = int(S.get("max_file_mb", 60))

# obvious non-images to leave on the remote; anything else is pulled and then
# probed with Pillow, so extensionless files (Drive often stores them that way)
# still work.
SKIP_EXTS = {
    ".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".3gp",
    ".pdf", ".zip", ".gz", ".tar", ".7z", ".rar",
    ".txt", ".md", ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    ".mp3", ".wav", ".aac", ".json", ".csv",
}


def log(*a: object) -> None:
    print(*a, flush=True)


def run_rclone() -> None:
    ORIG.mkdir(parents=True, exist_ok=True)
    cmd = [
        "rclone", "sync", S["remote"], str(ORIG),
        "--config", RCLONE_CONFIG,
        "--fast-list",
        "--transfers", "4",
        "--checkers", "8",
        "--max-size", f"{MAX_FILE_MB}M",
    ]
    for ext in sorted(SKIP_EXTS):
        cmd += ["--exclude", f"*{ext}", "--exclude", f"*{ext.upper()}"]
    log("+", " ".join(cmd))
    subprocess.run(cmd, check=True)


def flat_name(rel: Path) -> str:
    """originals/2024/img_1.jpg -> 2024__img_1.jpg so processed/ stays flat."""
    return str(rel.with_suffix(".jpg")).replace(os.sep, "__")


def process() -> None:
    PROC.mkdir(parents=True, exist_ok=True)
    originals = [
        p for p in ORIG.rglob("*")
        if p.is_file() and p.suffix.lower() not in SKIP_EXTS
    ]
    wanted: set[str] = set()

    for src in sorted(originals):
        out = PROC / flat_name(src.relative_to(ORIG))
        wanted.add(out.name)
        if out.exists() and out.stat().st_mtime >= src.stat().st_mtime:
            continue
        try:
            with Image.open(src) as im:
                im = ImageOps.exif_transpose(im)
                im = im.convert("RGB")
                im.thumbnail((MAX_DIM, MAX_DIM), Image.LANCZOS)
                tmp = out.with_suffix(".tmp")
                im.save(tmp, "JPEG", quality=QUALITY, optimize=True, progressive=True)
                tmp.replace(out)
            os.utime(out, (src.stat().st_mtime, src.stat().st_mtime))
            log("processed", src.name, "->", out.name)
        except Exception as e:  # noqa: BLE001 - one bad file shouldn't stop the run
            print("SKIP", src, "-", e, file=sys.stderr, flush=True)

    for p in PROC.glob("*.jpg"):
        if p.name not in wanted:
            p.unlink(missing_ok=True)
            log("pruned", p.name)


def write_manifest() -> None:
    photos = []
    for p in sorted(PROC.glob("*.jpg")):
        try:
            with Image.open(p) as im:
                w, h = im.size
        except Exception:  # noqa: BLE001
            continue
        photos.append(
            {
                "src": f"photos/{p.name}",
                "w": w,
                "h": h,
                "orientation": "portrait" if h > w else "landscape",
            }
        )
    tmp = MANIFEST.with_suffix(".tmp")
    tmp.write_text(
        json.dumps(
            {
                "generated": datetime.now(timezone.utc).isoformat(),
                "count": len(photos),
                "photos": photos,
            },
            indent=2,
        )
    )
    tmp.replace(MANIFEST)
    log(f"manifest: {len(photos)} photos")


def main() -> int:
    try:
        run_rclone()
    except FileNotFoundError:
        print("rclone not installed", file=sys.stderr)
        return 1
    except subprocess.CalledProcessError as e:
        # network hiccup etc - still rebuild the manifest from what we have
        print(f"rclone failed ({e.returncode}); rebuilding manifest from cache", file=sys.stderr)
    process()
    write_manifest()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
