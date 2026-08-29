#!/usr/bin/env python3
"""Dump a Samsung Frame TV's Art Mode gallery: a JSON list + a thumbnail per item.

Full-resolution originals are NOT retrievable — Samsung exposes no export API.
Thumbnails are low-res (a few hundred px), useful only for identifying what to
re-source from the real originals.

    python3 -m pip install samsungtvws
    python3 scripts/frame-art-dump.py <TV_IP> [out_dir]

The TV must be reachable on the network (Art Mode standby is fine, not fully
off). On the first run the TV shows an "Allow this device?" prompt — accept it
with the remote, then re-run.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from samsungtvws import SamsungTVWS
except ImportError:
    sys.exit("pip install samsungtvws first")


def main() -> int:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    host = sys.argv[1]
    out = Path(sys.argv[2] if len(sys.argv) > 2 else "frame-art")
    out.mkdir(parents=True, exist_ok=True)

    tv = SamsungTVWS(
        host=host, port=8002,
        token_file=str(out / ".token"), name="frame-art-dump",
    )
    art = tv.art()

    items = art.available()
    (out / "art-list.json").write_text(json.dumps(items, indent=2))
    print(f"{len(items)} items -> {out / 'art-list.json'}")

    for it in items:
        cid = it.get("content_id") or it.get("id")
        if not cid:
            continue
        try:
            data = art.get_thumbnail(cid)
            (out / f"{cid}.jpg").write_bytes(data)
            print("thumb", cid)
        except Exception as e:  # noqa: BLE001 - keep going on the rest
            print("skip ", cid, "-", e, file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
