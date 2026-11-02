#!/bin/bash
set -e

# Usage: ./scripts/pack_release.sh <CAMERA_MODEL> <OUT_VERSION> [BASE_VERSION]
# Example: ./scripts/pack_release.sh y203c 0.6.0 0.5.8
#
# Env:
#   PACK_PROFILE=full|slim   (default: full)
#     full — public release: keep ONVIF, alt-RTSP, proxychains, SFTP, timelapse helpers
#     slim — drop optional modules for /home headroom (no ONVIF/SFTP/alt-RTSP/proxychains/timelapse bins)
#   PACK_STRIP_EXTRA=imggrabber,jq   comma-separated extra basenames to remove (any profile)

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
CAMERA_MODEL="${1:-y203c}"
OUT_VER="${2:-$(cat "$WORKSPACE/VERSION")}"
BASE_VER="${3:-0.5.8}"
PACK_PROFILE="${PACK_PROFILE:-full}"
PACK_STRIP_EXTRA="${PACK_STRIP_EXTRA:-}"
# Pin toolchain image by digest (borodiliz/yi-hack:latest resolved 2026-11-02)
YI_HACK_IMAGE="${YI_HACK_IMAGE:-borodiliz/yi-hack@sha256:3af230b23f26b0e5ddee942cd6b2a78da5eb7c8c6e8c615e453cd8b806a1b339}"
BASE_SHA_FILE="${BASE_SHA_FILE:-$WORKSPACE/scripts/base-firmware.sha256}"

case "$PACK_PROFILE" in
    full|slim) ;;
    *)
        echo "ERROR: PACK_PROFILE must be full or slim (got: $PACK_PROFILE)"
        exit 1
        ;;
esac

echo "========================================================================"
echo " Packaging Release Firmware: $CAMERA_MODEL v$OUT_VER (from v$BASE_VER)"
echo " PACK_PROFILE=$PACK_PROFILE"
echo "========================================================================"

WORK_DIR="$WORKSPACE/.fw_build_$CAMERA_MODEL"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$WORKSPACE/out"

BASE_NAME="${CAMERA_MODEL}_${BASE_VER}.tgz"
echo "1. Downloading base release archive ($BASE_NAME)..."
curl -fsSL -o "$WORK_DIR/$BASE_NAME" "https://github.com/roleoroleo/yi-hack-MStar/releases/download/${BASE_VER}/${BASE_NAME}"

echo "1b. Verifying SHA256 of base archive..."
EXPECTED_SHA="$(awk -v f="$BASE_NAME" '$2 == f { print $1; exit }' "$BASE_SHA_FILE")"
if [ -z "$EXPECTED_SHA" ]; then
    echo "ERROR: No checksum for $BASE_NAME in $BASE_SHA_FILE — refuse to pack unverified base."
    exit 1
fi
if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL_SHA="$(sha256sum "$WORK_DIR/$BASE_NAME" | awk '{print $1}')"
else
    ACTUAL_SHA="$(shasum -a 256 "$WORK_DIR/$BASE_NAME" | awk '{print $1}')"
fi
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "ERROR: SHA256 mismatch for $BASE_NAME"
    echo "  expected: $EXPECTED_SHA"
    echo "  actual:   $ACTUAL_SHA"
    exit 1
fi
echo "    OK $ACTUAL_SHA"
mv "$WORK_DIR/$BASE_NAME" "$WORK_DIR/base.tgz"

echo "2. Extracting partitions..."
tar -zxvf "$WORK_DIR/base.tgz" -C "$WORK_DIR"

echo "3. Extracting home JFFS2 partition via jefferson inside container..."
docker run --rm --platform linux/amd64 \
  --entrypoint bash \
  -v "$WORKSPACE:/workspace" \
  -w /workspace \
  "$YI_HACK_IMAGE" \
  -c "python /usr/local/bin/jefferson /workspace/.fw_build_${CAMERA_MODEL}/home_${CAMERA_MODEL} -d /workspace/.fw_build_${CAMERA_MODEL}/extracted && chmod -R 777 /workspace/.fw_build_${CAMERA_MODEL}"
FS_DIR="$WORK_DIR/extracted/fs_1"
if [ ! -d "$FS_DIR/yi-hack" ]; then
    echo "ERROR: fs_1/yi-hack directory not found in extracted partition."
    exit 1
fi

echo "4. Overlaying updated binaries, scripts and WebUI..."
# Always rebuild www so PACK_PROFILE (gz policy) is applied
rm -rf "$WORKSPACE/src/www/_install/www"
(cd "$WORKSPACE/src/www" && PACK_PROFILE="$PACK_PROFILE" ./compile.www)
# Replace www entirely so base ONVIF XML/.gz assets do not remain (large on slim)
rm -rf "$FS_DIR/yi-hack/www"
mkdir -p "$FS_DIR/yi-hack/www"
# www/record is a dangling host symlink to /tmp/sd/record — copy tree without it, then recreate
(
  cd "$WORKSPACE/src/www/_install/www"
  tar -cf - --exclude=record . | tar -xf - -C "$FS_DIR/yi-hack/www"
)
ln -sfn /tmp/sd/record "$FS_DIR/yi-hack/www/record"

cp -f "$WORKSPACE/src/rRTSPServer/_install/bin/rRTSPServer" "$FS_DIR/yi-hack/bin/rRTSPServer"
cp -f "$WORKSPACE/src/h264grabber/_install/bin/h264grabber" "$FS_DIR/yi-hack/bin/h264grabber"
ln -sf /home/yi-hack/bin/h264grabber "$FS_DIR/yi-hack/bin/h264grabber_h"
ln -sf /home/yi-hack/bin/h264grabber "$FS_DIR/yi-hack/bin/h264grabber_l"

# Overlay all boot/service scripts (includes common.sh + refactored system/service)
mkdir -p "$FS_DIR/yi-hack/script"
cp -f "$WORKSPACE/src/static/static/home/yi-hack/script/"*.sh "$FS_DIR/yi-hack/script/"
cp -rf "$WORKSPACE/src/static/static/home/yi-hack/script/mqtt_advertise/"* "$FS_DIR/yi-hack/script/mqtt_advertise/"
# Preserve blacklist directory from base if present; also overlay from static if exists
if [ -d "$WORKSPACE/src/static/static/home/yi-hack/script/blacklist" ]; then
    mkdir -p "$FS_DIR/yi-hack/script/blacklist"
    cp -rf "$WORKSPACE/src/static/static/home/yi-hack/script/blacklist/"* "$FS_DIR/yi-hack/script/blacklist/"
fi
echo "$OUT_VER" > "$FS_DIR/yi-hack/version"
echo "$PACK_PROFILE" > "$FS_DIR/yi-hack/pack_profile"

strip_basename() {
    local name="$1"
    local found
    found="$(find "$FS_DIR/yi-hack" \( -type f -o -type l \) \( -name "$name" -o -name "${name}.so*" \) 2>/dev/null || true)"
    if [ -n "$found" ]; then
        echo "$found" | while read -r p; do
            [ -n "$p" ] || continue
            echo "    strip: $p"
            rm -f "$p"
        done
    fi
}

strip_optional_modules() {
    echo "4b. Stripping optional modules for PACK_PROFILE=$PACK_PROFILE..."
    local names=""
    if [ "$PACK_PROFILE" = "slim" ]; then
        # Always safe on slim: unused when features off / not needed for minimal boot
        names="rtsp_server_yi proxychains4 libproxychains4.so h264grabber2 avimake minimp4_yi"
        # Slim = no ONVIF / no SFTP (documented)
        names="$names onvif_notify_server wsd_simple_server sftp-server"
    fi
    if [ -n "$PACK_STRIP_EXTRA" ]; then
        local extra
        extra="$(echo "$PACK_STRIP_EXTRA" | tr ',' ' ')"
        names="$names $extra"
    fi
    if [ -z "$names" ]; then
        echo "    (nothing to strip)"
        return
    fi
    for n in $names; do
        strip_basename "$n"
    done
}

strip_optional_modules

echo "5. Re-packing JFFS2 home partition with mkfs.jffs2..."
docker run --rm --platform linux/amd64 \
  --entrypoint bash \
  -v "$WORKSPACE:/workspace" \
  -w /workspace \
  "$YI_HACK_IMAGE" \
  -c "mkfs.jffs2 -l -e 0x10000 -r /workspace/.fw_build_${CAMERA_MODEL}/extracted/fs_1 -o /workspace/.fw_build_${CAMERA_MODEL}/home_${CAMERA_MODEL} && chmod -R 777 /workspace/.fw_build_${CAMERA_MODEL}"

HOME_SIZE="$(stat -f%z "$WORK_DIR/home_${CAMERA_MODEL}" 2>/dev/null || stat -c%s "$WORK_DIR/home_${CAMERA_MODEL}")"
# JFFS2 HOME partition is ~12.2MB (12845056 typical); leave margin for compression variance
HOME_MTD_BYTES="${HOME_MTD_BYTES:-12845056}"
EST_FREE=$((HOME_MTD_BYTES - HOME_SIZE))
echo "    home_${CAMERA_MODEL} size: $HOME_SIZE bytes"
echo "    estimated free after flash (approx): $EST_FREE bytes ($((EST_FREE / 1024)) KiB)"

echo "6. Creating release distribution archive..."
OUT_TGZ="$WORKSPACE/out/${CAMERA_MODEL}_${OUT_VER}.tgz"
if [ "$PACK_PROFILE" = "slim" ]; then
    OUT_TGZ="$WORKSPACE/out/${CAMERA_MODEL}_${OUT_VER}-slim.tgz"
fi
(
  cd "$WORK_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}" > SHA256SUMS
  else
    shasum -a 256 "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}" > SHA256SUMS
  fi
  tar -zcvf "$OUT_TGZ" "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}" SHA256SUMS
)

# Persist size report for headroom checks
mkdir -p "$WORKSPACE/out"
{
  echo "camera=$CAMERA_MODEL"
  echo "version=$OUT_VER"
  echo "profile=$PACK_PROFILE"
  echo "home_bytes=$HOME_SIZE"
  echo "home_mtd_bytes=$HOME_MTD_BYTES"
  echo "est_free_bytes=$EST_FREE"
  echo "archive=$OUT_TGZ"
} > "$WORKSPACE/out/${CAMERA_MODEL}_${OUT_VER}-${PACK_PROFILE}.headroom.txt"

rm -rf "$WORK_DIR"
echo "========================================================================"
echo " SUCCESS: Generated $OUT_TGZ"
echo " Size: $(ls -lh "$OUT_TGZ" | awk '{print $5}')"
echo " Headroom report: out/${CAMERA_MODEL}_${OUT_VER}-${PACK_PROFILE}.headroom.txt"
echo "========================================================================"
