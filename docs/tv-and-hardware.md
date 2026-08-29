# Hardware & TV setup

## Bill of materials (~$90)

| Item | Spec | Notes |
|---|---|---|
| Raspberry Pi 4 | 2GB | Handles 4K stills fine |
| PSU | Official 27W USB-C (5V/3A) | Pi 4 is fussy about undervoltage |
| microSD | 32GB A2 | Root stays read-only (Overlay FS) so wear is low |
| USB stick | 16–32GB | Mounted at `/data` — photo cache + logs + secrets |
| micro-HDMI → HDMI cable | 0.5–1 m | Pi HDMI0 (the one nearest USB-C) → One Connect box |
| Passive heatsink case | e.g. FLIRC | Slideshow is light load; no fan needed |
| Smart plug | (already owned) | Feeds **both** the Pi and the TV via a short 2-way lead |

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

## Pi OS

- Raspberry Pi OS **Lite 64-bit** (Bookworm). Flash with Raspberry Pi Imager;
  in the gear menu set hostname (`frame-pi`), enable SSH, add Wi-Fi + your key.
- After first boot: `git clone <repo> /opt/frame-tv-sync` then
  `sudo /opt/frame-tv-sync/scripts/install.sh`.
- Mount the USB stick at `/data` (add to `/etc/fstab` by `PARTUUID`, e.g.
  `PARTUUID=xxxx  /data  ext4  defaults,noatime  0  2`). Do this **before**
  enabling Overlay FS.
- `sudo raspi-config` → **Performance → Overlay File System → enable**, and set
  the boot partition read-only too. Now pulling the plug can't corrupt the card.
  (To make config changes later: disable Overlay FS, edit, re-enable.)

## What this is / isn't

This drives the TV as an **HDMI source**, not Samsung Art Mode. The app
reproduces the *look* (mount-board matte, slow rotation, evening dimming,
anti burn-in) but the TV is a normal "on" input: higher power than Art Mode,
and no motion-sensor behaviour — power is handled entirely by the smart plug.
