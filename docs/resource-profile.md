# Resource profile (MStar / yi-hack)

What uses RAM/CPU at runtime vs what occupies `/home` flash space are different levers.

## Flash (/home) vs runtime

| Lever | Effect | How |
| :--- | :--- | :--- |
| `PACK_PROFILE=slim` | Frees NAND in `/home/yi-hack` (ONVIF/SFTP/alt-RTSP/proxychains/timelapse bins + no www `.gz`) | Build-time |
| `PACK_STRIP_EXTRA=imggrabber,...` | Extra optional strip | Build-time |
| Feature flags in `system.conf` | Stops processes → frees RAM/CPU | Runtime |
| `DISABLE_CLOUD=yes` | Drops p2p/oss/watch_process path | Runtime |

Target after slim flash: **≥ ~2.5 MiB free** on `/home` (`scripts/check_home_headroom.sh`).

## Typical processes → feature flags

| Process | Role | Enable / disable |
| :--- | :--- | :--- |
| `rmm` | Stock media manager | Always (core) |
| `dispatch` | IPC mux | Always (core) |
| `cloud` | Stock cloud / buffer helper | Cloud path or buffer trick when cloud disabled |
| `h264grabber_l` / `_h` | FIFO video capture | `RTSP=yes` |
| `rRTSPServer` | RTSP daemon (default) | `RTSP=yes`, `RTSP_ALT` empty/standard |
| `rtsp_server_yi` | Alt RTSP (stripped in slim) | `RTSP_ALT=alternative` |
| `mqttv4` / `mqtt-config` | MQTT | Always starts mqttv4; config/advertise when `MQTT=yes` |
| `httpd` | Web UI | `HTTPD=yes` + USERNAME set |
| `dropbear` | SSH | `SSHD=yes` |
| `pure-ftpd` / busybox ftpd | FTP | `FTPD=yes` |
| `onvif_notify_server` / WSDD | ONVIF (not in slim image) | `ONVIF=yes` / `ONVIF_WSDD=yes` |
| `mdnsd` | mDNS | `MDNSD=yes` |
| `imggrabber` | Snapshots / thumbs | `SNAPSHOT=yes` (and cron when `SNAPSHOT_VIDEO`) |
| `mp4record` | Local recording | Cloud path, or `REC_WITHOUT_CLOUD=yes` |
| `crond` | Cron jobs | Always after boot scripts |

## How to sample on-camera

```sh
# RSS (kB) from /proc
for p in rmm rRTSPServer h264grabber mqttv4 httpd dispatch cloud mdnsd; do
  pid=$(pidof "$p" 2>/dev/null | awk '{print $1}')
  [ -n "$pid" ] || continue
  rss=$(awk '/VmRSS/{print $2}' /proc/$pid/status 2>/dev/null)
  echo "$p pid=$pid VmRSS_kB=$rss"
done

# Busybox overview
ps w
free
```

Or via helper: `scripts/cam_ssh.sh --host 192.168.x.y '...'`.

## Baseline notes (sampled 2026-11-02)

Both cams: `DISABLE_CLOUD=yes`, `RTSP=yes` (both streams + AAC), `MQTT=yes`, `ONVIF=no`, `HTTPD/SSHD/FTPD/MDNSD=yes`, `SNAPSHOT=yes`.

| Host | FW | /home free | Notable VmRSS (kB) |
| :--- | :--- | ---: | :--- |
| 192.168.2.62 | 0.3.1 | ~1356 KiB | rmm 13224, rRTSPServer 4240, mqttv4 2268, dispatch 1500, cloud 1288, mdnsd 1208, mqtt-config 1148, h264grabber_h 1108, h264grabber_l 992, pure-ftpd 836, httpd 792 |
| 192.168.2.63 | 0.3.0 | ~1956 KiB | rmm 11324, rRTSPServer 4312, mqttv4 1872, dispatch 1452, cloud 1284, mdnsd 1240, mqtt-config 1148, h264grabber_h 1092, h264grabber_l 964, httpd 784, pure-ftpd 716 |

CPU time (busybox `ps`): stock `rmm` dominates wall time; next are `rRTSPServer` and the two `h264grabber_*` when RTSP is up.

`PACK_PROFILE=slim` y203c 0.3.2 pack report: home image ~10.0 MB → **est. free ~2737 KiB** after flash (target ≥2560).

## Pack profiles

```bash
# Public / full feature set (default)
./scripts/pack_release.sh y203c 0.3.2

# Slim home image (no ONVIF/SFTP/alt-RTSP/proxychains/timelapse helpers; plain www only)
PACK_PROFILE=slim ./scripts/pack_release.sh y203c 0.3.2

# Slim + drop imggrabber explicitly
PACK_PROFILE=slim PACK_STRIP_EXTRA=imggrabber ./scripts/pack_release.sh y203c 0.3.2
```
