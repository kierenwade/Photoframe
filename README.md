# frame-tv-sync

Turn a Samsung Frame TV into a Google-Drive photo frame using a Raspberry Pi on
the HDMI input. The Pi syncs a Drive folder, downscales the photos, and shows
them full-screen with a mount-board matte, slow cross-fades, evening dimming and
anti burn-in jitter.

> **Not** Samsung Art Mode. The TV runs as a normal HDMI source; this app
> reproduces the *look*. Power on/off is done with a smart plug feeding both the
> Pi and the TV. See [docs/tv-and-hardware.md](docs/tv-and-hardware.md).

## How it works

```
Smart plug on ─► Pi boots (read-only OS) ─► CEC: TV on + select this input
                     │
   frame-serve  ─────┤  localhost:8080  (config.json, manifest.json, /photos/*)
   frame-kiosk  ─────┤  cage + Chromium --kiosk  ─►  app/  slideshow
   frame-sync   ─────┘  hourly: rclone (Drive, read-only) ─► downscale ─► manifest.json
```

| Unit | Type | Job |
|---|---|---|
| `frame-serve.service` | daemon | tiny stdlib web server for the kiosk |
| `frame-kiosk.service` | daemon | Chromium full-screen via the `cage` compositor |
| `frame-cec.service` | boot oneshot | power TV on, switch to the Pi's input (retries) |
| `frame-sync.timer` → `frame-sync.service` | timer | pull photos from Drive, resize, rebuild manifest |

## Layout

```
config.toml              all tunables (interval, matte colour, dimming, lat/long)
bin/sync.py              rclone pull -> Pillow downscale -> manifest.json
bin/serve.py             localhost web server (stdlib only)
bin/cec-assert.sh        boot-time CEC power-on + active-source
bin/start-kiosk.sh       cage + chromium launcher
app/                     index.html, style.css, sun.js, slideshow.js
systemd/                 the four units above
scripts/install.sh       one-time Pi setup
scripts/deploy.sh        rsync changes from your Mac + restart services
docs/                    Google Drive service account, hardware, TV settings
```

## Setup (short version)

1. **Hardware + Pi OS + TV** — [docs/tv-and-hardware.md](docs/tv-and-hardware.md).
2. `git clone <repo> /opt/frame-tv-sync && sudo /opt/frame-tv-sync/scripts/install.sh`
3. **Google Drive** — [docs/gdrive-service-account.md](docs/gdrive-service-account.md):
   create a service account, share the folder, drop `gdrive-sa.json` +
   `rclone.conf` into `/data/secrets/`.
4. Test the pull:
   `sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py`
5. `sudo raspi-config` → enable **Overlay File System**, then reboot.
6. Turn the smart plug off and on — photos should appear in ~30–60 s.

## Configuration

Everything lives in [`config.toml`](config.toml). The slideshow re-reads it
every 30 s, so most changes apply without a restart:

| Key | Default | Meaning |
|---|---|---|
| `slideshow.interval_seconds` | `60` | seconds per photo |
| `slideshow.min_interval_seconds` | `15` | hard floor |
| `slideshow.shuffle` | `true` | random order |
| `slideshow.transition` / `transition_ms` | `crossfade` / `1200` | fade style/length |
| `sync.remote` | `gdrive:` | rclone remote (folder set by `root_folder_id`) |
| `sync.interval_minutes` | `60` | also set `frame-sync.timer` `OnUnitActiveSec` to match |
| `sync.max_dimension` | `3840` | long-edge downscale target |
| `display.matte_color` | `#EDEAE3` | mount board behind the photo |
| `display.matte_min_border_pct` | `4` | matte inset from screen edge (vmin) |
| `display.anti_burnin_*` | `1` px / `90` s | periodic pixel nudge |
| `dimming.enabled` | `true` | evening dim/warm |
| `dimming.latitude` / `longitude` | London | for local sunrise/sunset |
| `dimming.night_brightness` / `night_warmth` | `0.75` / `0.12` | after-dark look |
| `dimming.fade_minutes` | `30` | ramp width around sunrise/sunset |

## Develop / preview on a Mac

```bash
mkdir -p /data/photos/processed          # or edit PHOTOS in bin/serve.py
cp ~/somephotos/*.jpg /data/photos/processed/
python3 bin/sync.py 2>/dev/null || true  # just to write a manifest (needs Pillow)
python3 bin/serve.py                     # open http://localhost:8080
```

## Troubleshooting

| Symptom | Check |
|---|---|
| Black screen, no photos | `journalctl -u frame-kiosk -b`; is `frame-serve` up? `curl localhost:8080/manifest.json` |
| "Waiting for photos…" forever | `journalctl -u frame-sync -b`; `rclone --config /data/secrets/rclone.conf lsd gdrive:` |
| TV stays off / wrong input | `docs/tv-and-hardware.md` Anynet+; `cat /data/logs/cec.log`; try `echo 'as' \| cec-client -s -d 1` |
| Photos look over-bright at night | lower `dimming.night_brightness`; verify `latitude`/`longitude` |
| Config edits don't apply | Overlay FS is on — disable in `raspi-config`, edit, re-enable |
| SD card corruption after power cuts | Overlay FS not enabled, or `/data` not on the USB stick |
