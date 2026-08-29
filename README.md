# frame-tv-sync

Turn a Samsung Frame TV into a Google-Drive photo frame using a Raspberry Pi on
the HDMI input. The Pi syncs a Drive folder, renders each photo to the TV's
exact resolution so it fills the screen, and shows them with slow cross-fades,
evening dimming and anti burn-in jitter.

> **Not** Samsung Art Mode. The TV runs as a normal HDMI source; this app
> reproduces the *look*. Power on/off is done with a smart plug feeding both the
> Pi and the TV. See [docs/tv-and-hardware.md](docs/tv-and-hardware.md).

## How it works

```
Smart plug on ─► Pi boots (read-only OS) ─► CEC: TV on + select this input
                     │
   frame-serve  ─────┤  localhost:8080  (config.json, manifest.json, /photos/*)
   kiosk (tty1)  ────┤  sway + Chromium --kiosk  ─►  app/  slideshow
   frame-sync   ─────┘  hourly: rclone (Drive, read-only) ─► downscale ─► manifest.json
```

**One SD card, three partitions:** `bootfs` (FAT32) + `rootfs` (ext4, **read-only**
via Overlay FS) + `frame-data` (ext4, **read-write**, mounted at `/data` — holds
photos, logs, secrets and the live `config.toml`). Yanking the smart plug can't
corrupt the OS.

| Unit | Type | Job |
|---|---|---|
| `frame-serve.service` | daemon | tiny stdlib web server for the kiosk |
| tty1 autologin → `bin/start-kiosk.sh` | login shell | Chromium full-screen via the `sway` compositor in kiosk mode (a systemd service cannot get a seat for the compositor on this OS) |
| `frame-cec.service` | boot oneshot | power TV on, switch to the Pi's input (retries) |
| `frame-sync.timer` → `frame-sync.service` | timer | pull photos from Drive, resize, rebuild manifest |

## Layout

```
config.toml               default tunables — copied to /data/config.toml on install
chromium-policy.json      managed kiosk policy -> /etc/chromium/policies/managed/ on install
bin/sync.py               rclone pull -> Pillow downscale -> manifest.json
bin/serve.py              localhost web server (stdlib only)
bin/cec-assert.sh         boot-time CEC power-on + active-source
bin/start-kiosk.sh        sway + chromium kiosk launcher
app/                      index.html, style.css, sun.js, slideshow.js
systemd/                  the four units above
scripts/setup-storage.sh  size the OS partition + carve the writable /data partition
scripts/install.sh        one-time Pi setup
scripts/deploy.sh         rsync changes from your Mac + restart services
docs/                     Google Drive service account, hardware, TV settings
```

## Setup (short version)

Full detail — including the cloud-init flash edits — in
[docs/tv-and-hardware.md](docs/tv-and-hardware.md).

1. **Flash** Pi OS Lite 64-bit (Imager customisation on: user, Wi-Fi, **Enable SSH**).
   On `bootfs`: remove `resize` from `cmdline.txt` and append `growpart: {mode: "off"}`
   + `resize_rootfs: false` to `user-data` — stops `/` expanding to fill the card.
2. First boot, SSH in, then lay out storage (**run twice**, it reboots between):
   ```bash
   curl -fsSL https://raw.githubusercontent.com/kierenwade/Photoframe/main/scripts/setup-storage.sh -o /tmp/setup-storage.sh
   sudo bash /tmp/setup-storage.sh     # edits table, reboots
   sudo bash /tmp/setup-storage.sh     # grows /, formats + mounts /data
   ```
3. Install:
   ```bash
   sudo apt update && sudo apt install -y git
   sudo git clone https://github.com/kierenwade/Photoframe.git /opt/frame-tv-sync
   sudo /opt/frame-tv-sync/scripts/install.sh
   ```
4. **Google Drive** — [docs/gdrive-service-account.md](docs/gdrive-service-account.md):
   service account, share the folder, drop `gdrive-sa.json` + `rclone.conf`
   into `/data/secrets/`.
5. Test the pull:
   `sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py`
6. `sudo /opt/frame-tv-sync/scripts/enable-overlay.sh`, then
   `sudo reboot` — read-only `/`, writable `/data`.
7. Turn the smart plug off and on — photos should appear in ~30–60 s.

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
| `sync.max_file_mb` | `60` | skip remote files larger than this |
| `render.width` / `height` | `1920` / `1080` | output size — set to your TV panel |
| `render.fit` | `cover` | `blur` (photo over a blurred zoom of itself), `cover` (fill + crop), `pad` (solid colour) |
| `render.pad_color` | `#000000` | used when `fit = pad` |
| `render.border_px` / `border_color` | `96` / `#EDEAE3` | even border on all sides (output px); `0` = none |
| `render.jpeg_quality` | `88` | changing any `render.*` re-renders the whole library |
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
| Black screen, no photos | `cat /data/logs/kiosk.log`; is `frame-serve` up? `curl 127.0.0.1:8080/manifest.json` |
| Black screen *with* a cursor | compositor up, Chromium not painting — `start-kiosk.sh` uses `--disable-gpu --no-sandbox` + positional URL. Pointer is hidden via sway `hide_cursor` |
| "Waiting for photos…" forever | `journalctl -u frame-sync -b`; `rclone --config /data/secrets/rclone.conf lsd gdrive:` |
| TV stays off / wrong input | `docs/tv-and-hardware.md` Anynet+; `cat /data/logs/cec.log`; try `echo 'as' \| cec-client -s -d 1` |
| Photos look over-bright at night | lower `dimming.night_brightness`; verify `latitude`/`longitude` |
| Restart the kiosk | `sudo pkill -x sway` (never `pkill -f chromium` — it also kills the launcher). |
| Config edits don't apply | edit `/data/config.toml`, not the repo copy; wait 30 s |
| SD card corruption after power cuts | Overlay FS not enabled; check `findmnt /` shows `overlay` |
| `setup-storage.sh` says "Not enough free space" | `growpart`/`resize` weren't disabled before first boot — `/` filled the card. Re-flash with the `cmdline.txt` + `user-data` edits from `docs/tv-and-hardware.md` |
| `apt` fails with "No space left" before `setup-storage.sh` | expected on the fresh image — run `setup-storage.sh` (twice) first; it needs only base tools |
| `/data` missing after reboot | `findmnt /data`; check the `LABEL=frame-data` line in `/etc/fstab` |
| `/` still tiny after `setup-storage.sh` | you only ran it once — run it again after the reboot to `resize2fs` |

## Maintenance

Nothing updates itself. Raspberry Pi OS doesn't auto-upgrade packages, and once
Overlay FS is on the root filesystem is read-only anyway (`apt` writes would land
in a RAM overlay and vanish on reboot). `install.sh` also disables the
`apt-daily` / `man-db` background timers since they can't achieve anything under
overlay.

Update deliberately, every few months or when a security fix matters:

```bash
sudo raspi-config nonint do_overlayfs 1 && sudo reboot   # disable overlay

sudo apt update && sudo apt full-upgrade
sudo -u frame git -C /opt/frame-tv-sync pull
sudo /opt/frame-tv-sync/.venv/bin/pip install -U -r /opt/frame-tv-sync/requirements.txt   # optional

sudo /opt/frame-tv-sync/scripts/enable-overlay.sh && sudo reboot   # re-enable (keeps /data writable)
```

The box only makes outbound connections (Google Drive), so quarterly is plenty.

To change **slideshow settings** you do *not* need any of this — edit
`/data/config.toml` (writable under overlay) and the app picks it up within 30 s.
