# Google Drive access via a service account

The Pi reads **one shared folder**, read-only. A stolen key therefore reaches
that folder and nothing else in your Drive.

## 1. Create the service account (~5 min, free)

1. <https://console.cloud.google.com/> → create a project, e.g. `frame-tv`.
2. **APIs & Services → Library → Google Drive API → Enable**.
3. **APIs & Services → Credentials → Create credentials → Service account**.
   - Name: `frame-tv-pi`. No roles needed. Done.
4. Open the new service account → **Keys → Add key → Create new key → JSON**.
   A `*.json` file downloads. This is the only secret.
5. Note the service account's email — looks like
   `frame-tv-pi@frame-tv-xxxxx.iam.gserviceaccount.com`.

## 2. Share the photo folder with it

In Google Drive, right-click your photos folder → **Share** → paste the service
account email → role **Viewer** → send.

Get the folder id from its URL:
`https://drive.google.com/drive/folders/`**`1AbCd...XYZ`** ← that trailing part.

## 3. Put the files on the Pi

```bash
# copy the downloaded key over, then:
sudo install -o frame -g frame -m 600 ~/frame-tv-pi-*.json /data/secrets/gdrive-sa.json
```

Create `/data/secrets/rclone.conf`:

```ini
[gdrive]
type = drive
scope = drive.readonly
service_account_file = /data/secrets/gdrive-sa.json
root_folder_id = 1AbCd...XYZ
```

```bash
sudo chown frame:frame /data/secrets/rclone.conf
sudo chmod 600 /data/secrets/rclone.conf
```

## 4. Test

```bash
rclone --config /data/secrets/rclone.conf lsd gdrive:
sudo -u frame /opt/frame-tv-sync/.venv/bin/python /opt/frame-tv-sync/bin/sync.py
ls /data/photos/processed | head
```

## Rotating / revoking

- Revoke: Cloud Console → the service account → **Keys** → delete the key, or
  delete the service account. Access stops immediately.
- The folder share can also just be removed in Drive.
