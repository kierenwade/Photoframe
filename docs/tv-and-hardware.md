# Hardware & TV setup

## Bill of materials (~$90)

| Item | Spec | Notes |
|---|---|---|
| Raspberry Pi 4 | 2GB | Handles 4K stills fine |
| PSU | Official 27W USB-C (5V/3A) | Pi 4 is fussy about undervoltage |
| microSD | **64GB A2** | Holds OS + photos. 32GB is fine for a smaller library (~6k photos) |
| micro-HDMI → HDMI cable | 0.5–1 m | Pi HDMI0 (the one nearest USB-C) → One Connect box |
| Passive heatsink case | e.g. FLIRC | Slideshow is light load; no fan needed |
| Smart plug | (already owned) | Feeds **both** the Pi and the TV via a short 2-way lead |

Photos are stored on the SD card itself, on a separate writable partition — no
USB stick. Downscaled JPEGs run ~2–4 MB each, so 64 GB leaves room for tens of
thousands.

## Wiring

```
Smart plug ── 2-way lead ──┬── Pi 4 PSU
                           └── Frame One Connect box PSU

Pi HDMI0 ── micro-HDMI→HDMI ── One Connect box  HDMI 1 (say)
```

Both devices power up together when the plug turns on. The Pi's boot CEC
script then wakes the TV and pulls the input to itself.

## TV settings (one time)

- **Settings → General/Connection → External Device Manager → Anynet+ (HDMI-CEC): On**
  (required for the power-on + input-switch to work).
- Rename the input the Pi is on to something obvious ("Frame").
- On that input, pick a **low-backlight picture preset** (Filmmaker / Movie,
  Backlight low, Local Dimming low). The Pi does fine brightness/warmth on top;
  it cannot lower the backlight itself over HDMI.
- If your firmware has *Settings → General → System Manager → (Start-screen /
  "return to last input")*, enable it as a belt-and-braces backup to CEC.

## SD card layout (one card, two usable volumes)

| # | Name | FS | Mount | State after setup |
|---|---|---|---|---|
| 1 | `bootfs` | FAT32 | `/boot/firmware` | read-only (rw only during OS updates) |
| 2 | `rootfs` | ext4 | `/` | **read-only** via Overlay FS — writes go to RAM, dropped on reboot |
| 3 | `frame-data` | ext4 | `/data` | **read-write** — photos, logs, secrets, live `config.toml` |

Pulling the plug can't corrupt partitions 1–2. Partition 3 uses ext4 journalling
+ `errors=remount-ro`; worst case is losing the last few photos pulled, which
re-sync from Drive on the next run.

## Pi OS setup

1. **Flash** Raspberry Pi OS **Lite 64-bit** (Bookworm) with Raspberry Pi Imager.
   When asked to apply OS customization, choose **No** — we configure headless
   by hand so the first-boot rootfs auto-expand does **not** consume the whole
   card (we need free space for partition 3).

2. Re-insert the card; macOS mounts **bootfs**. In that volume:
   - Edit `cmdline.txt` (keep it one line). Remove the token
     `init=/usr/lib/raspberrypi-sys-mods/firstboot` — or on older images
     `init=/usr/lib/raspi-config/init_resize.sh`. Leave everything else.
   - `touch /Volumes/bootfs/ssh`
   - Create `userconf.txt` containing `frame:<HASH>` where
     `HASH=$(printf 'YOURPASSWORD' | openssl passwd -6 -stdin)` (run on the Mac).
   - Create `wpa_supplicant.conf`:
     ```
     country=GB
     ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
     update_config=1
     network={
         ssid="YOUR_WIFI"
         psk="YOUR_WIFI_PASSWORD"
     }
     ```

3. Boot the Pi, then `ssh frame@frame-pi.local`.

4. ```bash
   sudo apt update && sudo apt install -y git parted
   sudo git clone <repo> /opt/frame-tv-sync
   sudo /opt/frame-tv-sync/scripts/make-data-partition.sh   # creates + mounts /data
   sudo /opt/frame-tv-sync/scripts/install.sh
   ```

5. Add the two secret files (see `gdrive-service-account.md`), then test:
   `sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py`

6. `sudo raspi-config` → **Performance → Overlay File System → Enable**, and
   answer **yes** to making the boot partition read-only. Reboot.

### Changing things later

- **Slideshow settings** (`interval_seconds`, matte colour, dimming, …): edit
  `/data/config.toml` any time — it's on the writable partition and the app
  re-reads it within 30 s.
- **Code / OS changes**: `sudo raspi-config` → disable Overlay FS → reboot →
  `git pull` (or edit) → re-enable Overlay FS → reboot.

## What this is / isn't

This drives the TV as an **HDMI source**, not Samsung Art Mode. The app
reproduces the *look* (mount-board matte, slow rotation, evening dimming,
anti burn-in) but the TV is a normal "on" input: higher power than Art Mode,
and no motion-sensor behaviour — power is handled entirely by the smart plug.
