#!/usr/bin/env python3
"""Pull photos from Google Drive, render them to the TV's size, write a manifest.

Flow:
  1. `rclone sync`  remote -> /data/photos/originals   (read-only service account)
  2. render each new/changed file -> /data/photos/processed/*.jpg
     every output is exactly [render] width x height so it fills the screen
  3. prune processed files whose original has gone
  4. write /data/photos/manifest.json  (the list the slideshow reads)

Incremental via mtime. If the [render] settings change, everything is
re-rendered (a signature file under processed/ tracks them).
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tomllib
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image, ImageColor, ImageEnhance, ImageFilter, ImageOps

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
R = CFG.get("render", {})

# on the Pi this is /data/photos; override for local dev with FRAME_PHOTOS_DIR
LOCAL = Path(os.environ.get("FRAME_PHOTOS_DIR", S["local_dir"]))
ORIG = LOCAL / "originals"
PROC = LOCAL / "processed"
MANIFEST = LOCAL / "manifest.json"
SIGFILE = PROC / ".render"

RCLONE_CONFIG = S.get("rclone_config", "/data/secrets/rclone.conf")
MAX_FILE_MB = int(S.get("max_file_mb", 60))

WIDTH = int(R.get("width", 3840))
HEIGHT = int(R.get("height", 2160))
FIT = str(R.get("fit", "blur")).lower()          # "blur" | "cover" | "pad"
PAD_COLOR = ImageColor.getrgb(str(R.get("pad_color", "#000000")))
BORDER_PX = max(0, min(int(R.get("border_px", 0)), WIDTH // 4, HEIGHT // 4))
BORDER_COLOR = ImageColor.getrgb(str(R.get("border_color", "#000000")))
QUALITY = int(R.get("jpeg_quality", S.get("jpeg_quality", 88)))
RENDER_SIG = f"v4|{WIDTH}x{HEIGHT}|{FIT}|{PAD_COLOR}|b{BORDER_PX}|{BORDER_COLOR}|q{QUALITY}"

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


def _fit(im: Image.Image, w: int, h: int) -> Image.Image:
    """Render `im` into a w x h RGB image using FIT."""
    if FIT == "cover":
        return ImageOps.fit(im, (w, h), Image.LANCZOS, centering=(0.5, 0.5))

    fg = im.copy()
    fg.thumbnail((w, h), Image.LANCZOS)
    off = ((w - fg.width) // 2, (h - fg.height) // 2)

    if FIT == "pad":
        canvas = Image.new("RGB", (w, h), PAD_COLOR)
        canvas.paste(fg, off)
        return canvas

    # "blur" (default): fill the gaps with a blurred, darkened zoom of the photo
    small = ImageOps.fit(im, (max(w // 6, 1), max(h // 6, 1)), Image.LANCZOS)
    small = small.filter(ImageFilter.GaussianBlur(18))
    small = ImageEnhance.Brightness(small).enhance(0.55)
    canvas = small.resize((w, h), Image.BICUBIC)
    canvas.paste(fg, off)
    return canvas


def render(im: Image.Image) -> Image.Image:
    """Return an exactly WIDTH x HEIGHT RGB image, with an even border if set."""
    im = ImageOps.exif_transpose(im).convert("RGB")
    if BORDER_PX <= 0:
        return _fit(im, WIDTH, HEIGHT)
    inner = _fit(im, WIDTH - 2 * BORDER_PX, HEIGHT - 2 * BORDER_PX)
    canvas = Image.new("RGB", (WIDTH, HEIGHT), BORDER_COLOR)
    canvas.paste(inner, (BORDER_PX, BORDER_PX))
    return canvas


def process() -> None:
    PROC.mkdir(parents=True, exist_ok=True)

    if SIGFILE.exists() and SIGFILE.read_text().strip() != RENDER_SIG:
        n = 0
        for p in PROC.glob("*.jpg"):
            p.unlink(missing_ok=True)
            n += 1
        log(f"render settings changed -> re-rendering all ({n} cleared)")

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
                rendered = render(im)
            tmp = out.with_suffix(".tmp")
            rendered.save(tmp, "JPEG", quality=QUALITY, optimize=True, progressive=True)
            tmp.replace(out)
            os.utime(out, (src.stat().st_mtime, src.stat().st_mtime))
            log("rendered", src.name, "->", out.name)
        except Exception as e:  # noqa: BLE001 - one bad file shouldn't stop the run
            print("SKIP", src, "-", e, file=sys.stderr, flush=True)

    for p in PROC.glob("*.jpg"):
        if p.name not in wanted:
            p.unlink(missing_ok=True)
            log("pruned", p.name)

    SIGFILE.write_text(RENDER_SIG)


def write_manifest() -> None:
    photos = [
        {"src": f"photos/{p.name}", "w": WIDTH, "h": HEIGHT}
        for p in sorted(PROC.glob("*.jpg"))
    ]
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
