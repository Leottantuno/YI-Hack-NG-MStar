# YI-Hack-NG-MStar

<p align="center">
  <img height="140" src="assets/logo.svg" alt="YI-Hack-NG-MStar logo">
</p>

<p align="center">
  <a href="https://github.com/Leottantuno/YI-Hack-NG-MStar/actions/workflows/build-rrtspserver.yml">
    <img src="https://github.com/Leottantuno/YI-Hack-NG-MStar/actions/workflows/build-rrtspserver.yml/badge.svg" alt="Build Status">
  </a>
  <a href="https://github.com/Leottantuno/YI-Hack-NG-MStar/releases">
    <img src="https://img.shields.io/github/v/release/Leottantuno/YI-Hack-NG-MStar?include_prereleases&label=Release" alt="Latest Release">
  </a>
  <a href="https://www.gnu.org/licenses/gpl-3.0">
    <img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="GPLv3 License">
  </a>
</p>

**YI-Hack-NG-MStar** (Next Generation for MStar platform) is an open-source custom firmware distribution for Yi security cameras based on the **MStar Infinity** SoC platform. Part of the **YI-Hack-NG** family, it introduces non-blocking RTSP streaming pipelines, deadlock prevention between video capture and streaming daemons, resilient watchdog process management, automated GitHub Actions container builds, and streamlined deployment tools. Starting from version **0.1.0**, it operates as an independent continuation with dedicated updates and releases.

---

## Key Highlights & Improvements

- **Reliable RTSP Streaming**:
  - `h264grabber`: Captures H.264 streams directly from kernel memory and writes to named FIFO pipes using non-blocking I/O (`O_RDWR | O_NONBLOCK`) with strict buffer pacing and safety guards to eliminate thread freezes and `SIGPIPE` aborts.
  - `rRTSPServer`: Powered by a custom Live555 `ByteStreamFifoSource` designed specifically for non-blocking asynchronous FIFO reads, preventing server thread lockups when players (VLC, Home Assistant, go2rtc, WebRTC) disconnect or reconnect.
- **Robust Service Lifecycle & Watchdog**:
  - `wd.sh`: Fully patched against infinite restart loops and monitoring race conditions. Services are sequenced gracefully without causing sporadic device reboots.
- **Cloud-Free & Local First**:
  - Complete control over camera telemetry: disable proprietary cloud features, access local web interface, RTSP, ONVIF, MQTT, SSH, FTP, and snapshot endpoints.
- **Modern CI & Cross-Compilation**:
  - Automated GitHub Actions builds compiling ARM binaries in Docker (`borodiliz/yi-hack`), resolving legacy Debian archive and DNS resolution issues.
- **Developer & Deployment Helpers**:
  - Integrated `scripts/cam_ssh.sh` utility to automate SSH/SCP deployment and hot-reloading on physical cameras.

---

## Table of Contents

- [Supported Cameras](#supported-cameras)
- [Architecture & How It Works](#architecture--how-it-works)
- [Features](#features)
- [Installation Guide](#installation-guide)
  - [Option A: Hot Update for Existing yi-hack Cameras (No Re-flash)](#option-a-hot-update-for-existing-yi-hack-cameras-no-re-flash)
  - [Option B: Fresh Installation from SD Card](#option-b-fresh-installation-from-sd-card)
- [Services & Configuration](#services--configuration)
  - [RTSP Video & Audio Stream URLs](#rtsp-video--audio-stream-urls)
  - [Snapshot API](#snapshot-api)
  - [Home Assistant Integration](#home-assistant-integration)
- [Development & Building](#development--building)
- [Heritage, Credits & License](#heritage-credits--license)
- [Disclaimer](#disclaimer)

---

## Supported Cameras

This firmware supports cameras running the **MStar Infinity** chipset family.

> [!NOTE]  
> If your camera uses a **HiSilicon Hi3518e** chipset, use [TheCrypt0/yi-hack-v4](https://github.com/TheCrypt0/yi-hack-v4).  
> If your camera uses an **Allwinner** chipset, use [roleoroleo/yi-hack-Allwinner-v2](https://github.com/roleoroleo/yi-hack-Allwinner-v2).

| Camera Model | Stock FW Version | File Prefix | Status / Notes |
| :--- | :---: | :---: | :--- |
| **Yi 1080p Home 4FUS** | 4.5.0* | `y203c` | Fully supported |
| **Yi 1080p Home 6FUS** | 4.5.0* | `y203c` | Fully supported |
| **Yi 1080p Home 9FUS** | 4.5.0* | `y203c` | Fully supported |
| **Yi 1080p Home BFUS** | 4.5.0* | `y203c` | Fully supported |
| **Yi 1080p Dome 6FUS** | 4.6.0* | `h201c` | Fully supported |
| **Yi 1080p Dome BFUS** | 4.6.0* | `h201c` | Fully supported |
| **Yi 1080p Dome 4FCN** | 4.6.0* | `h201c` | Fully supported |
| **Yi 1080p Home 4FUS** | 4.2.0* | `y25` | Supported |
| **Yi 1080p Home 9FUS** | 4.2.0* | `y25` | Supported |
| **XiaoYi Camera Y3 9FCN**| 4.2.0* | `y25` | Supported |
| **Yi 1080p Home 6FUS** | 2.1.0* | `y23` | Supported |
| **Yi 1080p Home 6FCN** | unknown | `y203c` | Supported |
| **Yi 1080p Home 4FCN** | unknown | `y23` | Supported |
| **Yi 1080p Home 5FCN** | 2.1.0* | `y23` | Supported |
| **YI Dome Camera X** | 4.0.0* | `y30` | Experimental |
| **YI Home Camera H7** | 4.4.0* | `h307` | Experimental |
| **ieGeek IE80** | 8.0.0* | `h305r` | Experimental |

*To determine if your camera is supported, verify that the first 4 characters of your serial number and the firmware version match an entry in the table above.*

---

## Architecture & How It Works

```
                        +----------------------------+
                        | MStar Kernel Video Driver  |
                        +--------------+-------------+
                                       |
                               (Kernel Memory)
                                       v
                              [ h264grabber ]
                                       |
                     (Non-blocking O_RDWR FIFO pipes)
                      /tmp/mstar_fifo_ch0 (High Res)
                      /tmp/mstar_fifo_ch1 (Low Res)
                                       v
                              [ rRTSPServer ]
                      (ByteStreamFifoSource Live555)
                                       |
                                       +<--- Audio: TinyAlsa wrapper -> /tmp/audio_fifo
                                       |
                                       v
                     RTSP Clients (VLC / go2rtc / HA)
```

1. **Video Streaming Pipeline**:
   - `h264grabber` reads encoded frames directly from MStar kernel device memory and feeds them into named pipes (`/tmp/mstar_fifo_ch0` and `/tmp/mstar_fifo_ch1`).
   - `rRTSPServer` reads from these pipes through an event-driven `ByteStreamFifoSource`.
   - By using non-blocking file descriptors on both sides, reader or writer delays do not lock up the opposing process.
2. **Audio Pipeline**:
   - A replacement `TinyAlsa` library intercepts audio from the kernel sound driver, downmixes 16-bit 16kHz stereo to mono, compresses it to 8-bit $\mu$-law (128 kbps), and pipes it to `rRTSPServer`.
3. **Supervision**:
   - `wd.sh` (watchdog script) oversees `rmm`, `h264grabber`, and `rRTSPServer` health, kicking the hardware watchdog (`/dev/watchdog`) to prevent system crashes while avoiding unnecessary service flapping.

---

## Features

- **RTSP Server**: High resolution, low resolution, and audio-only streaming endpoints.
- **ONVIF Server**: Profile S compliant (stream profiles, snapshots, PTZ controls and presets, WS-Discovery).
- **Snapshot Service**: HTTP GET snapshot endpoints with optional resolution selection and watermark removal.
- **Local Web Interface**: Intuitive management panel for configuration, network, and camera controls.
- **MQTT Broker Client**: Real-time event notifications for motion detection and baby crying detection.
- **Remote Access Protocols**:
  - SSH (`dropbear`)
  - Telnet (`busybox`)
  - FTP daemon
  - FTP Push: Automatic upload of motion mp4 recordings to an external FTP server.
- **Privacy & Cloud Isolation**: Complete switch to disable cloud connection, preventing camera video and telemetry from leaving your local network.

---

## Installation Guide

### Option A: Hot Update for Existing yi-hack Cameras (No Re-flash)

If your camera is already running `yi-hack-MStar` (v0.5.8 or similar), you **do not** need to re-flash your SD card. You can apply the new non-blocking RTSP pipeline and watchdog fixes directly:

1. Download the latest compiled binaries (`rRTSPServer`, `h264grabber`) from [GitHub Actions Artifacts or Releases](https://github.com/Leottantuno/YI-Hack-NG-MStar/actions).
2. Transfer the patched files to the camera:
   - Copy `rRTSPServer` and `h264grabber` to `/home/yi-hack/bin/` (or `/tmp/sd/yi-hack/bin/`).
   - Ensure execution permissions: `chmod +x /home/yi-hack/bin/rRTSPServer /home/yi-hack/bin/h264grabber`.
   - Copy `wd.sh` to `/home/yi-hack/script/wd.sh`.
3. Restart services or reboot the camera.

#### Quick deploy using `cam_ssh.sh`:
Create a `.env` file based on `.env.example`:
```bash
CAM_HOST=192.168.1.100
CAM_PW=your_password
```
Then run:
```bash
./scripts/cam_ssh.sh --scp src/rRTSPServer/_install/bin/rRTSPServer /tmp/sd/yi-hack/bin/rRTSPServer
./scripts/cam_ssh.sh --scp src/h264grabber/_install/bin/h264grabber /tmp/sd/yi-hack/bin/h264grabber
./scripts/cam_ssh.sh --scp src/static/static/home/yi-hack/script/wd.sh /tmp/sd/yi-hack/script/wd.sh
./scripts/cam_ssh.sh 'killall -9 rRTSPServer h264grabber; sleep 1; /home/yi-hack/script/wd.sh &'
```

---

### Option B: Fresh Installation from SD Card

1. Check that your camera model and firmware version are listed in [Supported Cameras](#supported-cameras) and note your **File Prefix** (e.g. `y203c`).
2. Format a micro-SD card (FAT32, 32GB or smaller recommended) using the camera's native format option or your computer.
3. Download the firmware release archive corresponding to your file prefix.
4. Extract the contents (e.g. `home_<prefix>` and `sys_<prefix>`) to the root of the SD card.
5. With the camera powered off, insert the SD card and plug in the power.
6. The status LED will illuminate yellow and flash for ~30 seconds while writing.
7. After reboot, the yellow LED will stay on for 1-2 minutes during the final initialization.
8. A steady blue LED indicates a successful Wi-Fi connection.
9. Open your web browser and navigate to `http://<IP-OF-CAMERA>` to configure settings.

---

## Services & Configuration

### RTSP Video & Audio Stream URLs

| Stream | URL | Description |
| :--- | :--- | :--- |
| **High Resolution (1080p)** | `rtsp://<CAM-IP>/ch0_0.h264` | Full resolution video + audio |
| **Low Resolution (360p)** | `rtsp://<CAM-IP>/ch0_1.h264` | Lower bandwidth video + audio |
| **Audio Only** | `rtsp://<CAM-IP>/ch0_2.h264` | G.711 $\mu$-law audio stream |

*If authentication is enabled in the Web UI, use `rtsp://<username>:<password>@<CAM-IP>/ch0_0.h264`.*

### Snapshot API

- **High Resolution**: `http://<CAM-IP>/cgi-bin/snapshot.sh`
- **Low Resolution without watermark**: `http://<CAM-IP>/cgi-bin/snapshot.sh?res=low&watermark=no`

---

### Home Assistant Integration

For zero-latency local streaming into Home Assistant, we recommend **go2rtc** or the **WebRTC Camera** custom component:

```yaml
# go2rtc.yaml configuration
streams:
  yi_camera_high:
    - rtsp://admin:password@192.168.1.100/ch0_0.h264
  yi_camera_low:
    - rtsp://admin:password@192.168.1.100/ch0_1.h264
```

Alternatively, integrate via Home Assistant's native generic camera platform or ONVIF integration.

---

## Development & Building

The binaries are cross-compiled for ARM (`arm-linux-gnueabihf`). You can compile locally using Docker without installing the proprietary toolchain on your host OS:

```bash
# Pull the preconfigured build toolchain container
docker pull borodiliz/yi-hack:latest

# Build h264grabber
cd src/h264grabber
./compile.h264grabber

# Build rRTSPServer
cd src/rRTSPServer
./init.rRTSPServer
./compile.rRTSPServer
```

Alternatively, push changes to the repository and download the artifacts automatically compiled by the GitHub Actions workflow in `.github/workflows/build-rrtspserver.yml`.

---

## Heritage, Credits & License

**YI-Hack-NG-MStar** is built upon the ingenuity and dedication of the open-source reverse engineering community:

- **[@roleoroleo](https://github.com/roleoroleo)**: Original creator and maintainer of [yi-hack-MStar](https://github.com/roleoroleo/yi-hack-MStar), [yi-hack-Allwinner](https://github.com/roleoroleo/yi-hack-Allwinner), and Home Assistant integration.
- **[@TheCrypt0](https://github.com/TheCrypt0)**: Author of [yi-hack-v4](https://github.com/TheCrypt0/yi-hack-v4), pioneering custom firmware on Yi devices.
- **[@PieVo](https://github.com/PieVo)**: Audio subsystem reverse engineering and TinyAlsa mono/$\mu$-law redirection.
- **@andy2301**: RTSP architecture and initial memory capture concepts.
- **[@borodiliz](https://github.com/borodiliz)**: Dockerized cross-compilation toolchain for MStar.

This software is released under the **GNU General Public License v3 (GPLv3)**. See the `LICENSE` file for details.

---

## Disclaimer

**USE AT YOUR OWN RISK.** Modifying camera firmware carries inherent risks of bricking hardware or voiding manufacturer warranties. The authors and contributors accept no responsibility for damages, data loss, or bricked devices. This project is developed purely for educational and local-privacy enhancement purposes.
