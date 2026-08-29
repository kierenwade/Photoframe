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

**One SD card, three partitions:** `bootfs` (FAT32) + `rootfs` (ext4, **read-only**
via Overlay FS) + `frame-data` (ext4, **read-write**, mounted at `/data` — holds
photos, logs, secrets and the live `config.toml`). Yanking the smart plug can't
corrupt the OS.

| Unit | Type | Job |
|---|---|---|
| `frame-serve.service` | daemon | tiny stdlib web server for the kiosk |
| `frame-kiosk.service` | daemon | Chromium full-screen via the `cage` compositor |
| `frame-cec.service` | boot oneshot | power TV on, switch to the Pi's input (retries) |
| `frame-sync.timer` → `frame-sync.service` | timer | pull photos from Drive, resize, rebuild manifest |

## Layout

```
config.toml                    default tunables — copied to /data/config.toml on install
bin/sync.py                    rclone pull -> Pillow downscale -> manifest.json
bin/serve.py                   localhost web server (stdlib only)
bin/cec-assert.sh              boot-time CEC power-on + active-source
bin/start-kiosk.sh             cage + chromium launcher
app/                           index.html, style.css, sun.js, slideshow.js
systemd/                       the four units above
scripts/make-data-partition.sh carve the writable /data partition out of the SD card
scripts/install.sh             one-time Pi setup
scripts/deploy.sh              rsync changes from your Mac + restart services
docs/                          Google Drive service account, hardware, TV settings
```

## Setup (short version)

1. **Flash + partition + TV** — [docs/tv-and-hardware.md](docs/tv-and-hardware.md).
   Flash Pi OS Lite 64-bit with the auto-expand disabled (so there's room for
   the `/data` partition), headless SSH/Wi-Fi via files on `bootfs`.
2. ```bash
   sudo apt install -y git parted
   sudo git clone <repo> /opt/frame-tv-sync
   sudo /opt/frame-tv-sync/scripts/make-data-partition.sh   # creates + mounts /data
   sudo /opt/frame-tv-sync/scripts/install.sh
   ```
3. **Google Drive** — [docs/gdrive-service-account.md](docs/gdrive-service-account.md):
   create a service account, share the folder, drop `gdrive-sa.json` +
   `rclone.conf` into `/data/secrets/`.
4. Test the pull:
   `sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py`
5. `sudo raspi-config` → enable **Overlay File System** (+ boot partition
   read-only), then reboot.
6. Turn the smart plug off and on — photos should appear in ~30–60 s.

## Configuration

On the Pi the live config is **`/data/config.toml`** (on the writable partition,
so it stays editable with Overlay FS on). The repo's [`config.toml`](config.toml)
is just the template that gets copied there on install. The slideshow re-reads it
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
export FRAME_PHOTOS_DIR=/tmp/frame-photos
mkdir -p "$FRAME_PHOTOS_DIR/processed"
cp ~/somephotos/*.jpg "$FRAME_PHOTOS_DIR/processed/"
python3 bin/sync.py 2>/dev/null || true   # writes a manifest.json (needs Pillow)
python3 bin/serve.py                      # open http://localhost:8080
```

`FRAME_PHOTOS_DIR`, `FRAME_CONFIG` and `FRAME_PORT` override the Pi defaults for
local work.

## Troubleshooting

| Symptom | Check |
|---|---|
| Black screen, no photos | `journalctl -u frame-kiosk -b`; is `frame-serve` up? `curl localhost:8080/manifest.json` |
| "Waiting for photos…" forever | `journalctl -u frame-sync -b`; `rclone --config /data/secrets/rclone.conf lsd gdrive:` |
| TV stays off / wrong input | `docs/tv-and-hardware.md` Anynet+; `cat /data/logs/cec.log`; try `echo 'as' \| cec-client -s -d 1` |
| Photos look over-bright at night | lower `dimming.night_brightness`; verify `latitude`/`longitude` |
| Config edits don't apply | edit `/data/config.toml`, not the repo copy; wait 30 s |
| SD card corruption after power cuts | Overlay FS not enabled; check `findmnt /` shows `overlay` |
| `make-data-partition.sh` says "no free space" | auto-expand wasn't disabled before first boot — re-flash, remove the `init=…firstboot` token from `cmdline.txt` |
| `/data` missing after reboot | `findmnt /data`; check the `LABEL=frame-data` line in `/etc/fstab` |
