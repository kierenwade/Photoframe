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
Pi HDMI0 ── micro-HDMI→HDMI ── One Connect box  HDMI 1 (say)
```

Power options:

- **Pi always on, own supply (simplest — recommended).** The TV can be on a
  switched/scheduled plug; when it powers on it returns to the Pi's input via
  the TV's "return to last input" setting (and CEC one-touch-play from the
  Pi's live signal). Root filesystem stays normal read-write.
- **Both on one switched plug.** They power up together and the Pi's boot CEC
  script wakes the TV + selects the input — but the Pi then gets an unclean
  shutdown every cycle, so run `scripts/enable-overlay.sh` to make `/`
  read-only.

## TV settings (one time)

- **Settings → General/Connection → External Device Manager → Anynet+ (HDMI-CEC): On**
  (required for the power-on + input-switch to work).
- Rename the input the Pi is on to something obvious ("Frame").
- On that input, pick a **low-backlight picture preset** (Filmmaker / Movie,
  Backlight low, Local Dimming low). The Pi does fine brightness/warmth on top;
  it cannot lower the backlight itself over HDMI.
- If your firmware has *Settings → General → System Manager → (Start-screen /
  "return to last input")*, enable it as a belt-and-braces backup to CEC.

## SD card layout

| # | Name | FS | Mount | Size | Notes |
|---|---|---|---|---|---|
| 1 | `bootfs` | FAT32 | `/boot/firmware` | ~512 MB | |
| 2 | `rootfs` | ext4 | `/` | **8 GiB** (fixed) | the OS; read-only if you run `enable-overlay.sh` |
| 3 | `frame-data` | ext4 | `/data` | rest of card | photos, logs, secrets, live `config.toml` |

`scripts/setup-storage.sh` builds this. The `/data` split keeps high-churn
photo/render writes off the OS partition; it mounts with ext4 journalling +
`errors=remount-ro`, so worst case after an unclean power loss is re-syncing the
last few photos from Drive.

## Pi OS setup

Current Raspberry Pi OS (Trixie) images configure first boot with **cloud-init**,
and both a `resize` kernel arg *and* cloud-init's `growpart` will expand `/` to
fill the whole card. We disable both so `setup-storage.sh` can lay out `/data`.

1. **Flash** Raspberry Pi OS **Lite 64-bit** with Raspberry Pi Imager. In the
   customisation dialog **do** set: hostname, username + password, Wi-Fi, locale,
   and **tick "Enable SSH" (password auth)**.

2. Re-insert the card; macOS mounts **bootfs**. In that volume:

   - Remove the `resize` token from `cmdline.txt` (stays one line):
     ```bash
     sed -i '' 's/ resize / /' /Volumes/bootfs/cmdline.txt
     cat /Volumes/bootfs/cmdline.txt          # verify: still one line, no "resize"
     ```
   - Stop cloud-init growing the filesystem — append to `user-data`:
     ```bash
     cat >> /Volumes/bootfs/user-data <<'EOF'

     # keep / at its image size; setup-storage.sh sizes it and adds /data
     growpart:
       mode: "off"
     resize_rootfs: false
     EOF
     ```
     (If you skipped "Enable SSH" in step 1, also add `ssh_pwauth: true` and a
     `runcmd:` with `- [ systemctl, enable, --now, ssh ]`.)

3. Eject, boot the Pi (first boot runs cloud-init then reboots once, ~3–5 min),
   then `ssh <user>@<hostname>.local`.

4. Lay out storage — run **twice**, it reboots itself in between:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/kierenwade/Photoframe/main/scripts/setup-storage.sh -o /tmp/setup-storage.sh
   sudo bash /tmp/setup-storage.sh          # edits the partition table, reboots
   # reconnect, then:
   sudo bash /tmp/setup-storage.sh          # grows /, formats + mounts /data
   ```
   `/` fresh off the image is nearly full, which is why this uses only
   base-image tools and runs before `apt`. Override the OS size with
   `sudo FRAME_ROOT_GB=6 bash /tmp/setup-storage.sh`.

5. Install:
   ```bash
   sudo apt update && sudo apt install -y git
   sudo git clone https://github.com/kierenwade/Photoframe.git /opt/frame-tv-sync
   sudo /opt/frame-tv-sync/scripts/install.sh
   ```

6. Add the two secret files (see `gdrive-service-account.md`).

7. **If the screen isn't 16:9** (a 1920×1200 monitor, an ultrawide, a 4K
   panel…), set the render size to the panel's exact resolution — otherwise the
   slideshow's `object-fit: cover` scales the image up and crops the sides
   (border included):
   ```bash
   # check the panel's resolution
   fbset -s 2>/dev/null | grep geometry || cat /sys/class/graphics/fb0/virtual_size
   # then, e.g. for 1920x1200:
   sudo -u frame sed -i 's/^width .*/width        = 1920/; s/^height .*/height       = 1200/' /data/config.toml
   ```

8. Test / render:
   `sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py`

9. `sudo reboot`. The photo should come up on the TV on its own.

10. Once it's confirmed working, make the root read-only:
    `sudo /opt/frame-tv-sync/scripts/enable-overlay.sh && sudo reboot`
    — `/` read-only (power cuts can't corrupt the OS), `/data` stays writable.
    Do this **last**; `/opt`, `apt` and `git pull` are frozen until you disable
    it (`sudo raspi-config nonint do_overlayfs 1 && sudo reboot`).

### Changing things later

- **Slideshow / dimming settings** (`interval_seconds`, `dimming.*`, …): edit
  `/data/config.toml` — the app re-reads it within 30 s.
- **`render.*`** (fit, size, quality): also edit `/data/config.toml`, but it
  takes effect on the next sync run or `sudo systemctl start frame-sync`, and
  re-renders the whole library.
- **Code / OS changes** (root is read-only, so overlay off first):
  ```bash
  sudo raspi-config nonint do_overlayfs 1 && sudo reboot
  sudo -u frame git -C /opt/frame-tv-sync pull      # and/or sudo apt full-upgrade, edit files
  sudo /opt/frame-tv-sync/scripts/enable-overlay.sh && sudo reboot
  ```

## What this is / isn't

This drives the TV as an **HDMI source**, not Samsung Art Mode. The app
reproduces the *look* (full-screen photos, slow rotation, evening dimming,
anti burn-in) but the TV is a normal "on" input: higher power than Art Mode,
and no motion-sensor behaviour — power is handled entirely by the smart plug.
