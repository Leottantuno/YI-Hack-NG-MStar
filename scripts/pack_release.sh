#!/bin/bash
set -e

# Usage: ./scripts/pack_release.sh <CAMERA_MODEL> <OUT_VERSION> [BASE_VERSION]
# Example: ./scripts/pack_release.sh y203c 0.6.0 0.5.8

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
CAMERA_MODEL="${1:-y203c}"
OUT_VER="${2:-$(cat "$WORKSPACE/VERSION")}"
BASE_VER="${3:-0.5.8}"
# Pin toolchain image by digest (borodiliz/yi-hack:latest resolved 2026-11-02)
YI_HACK_IMAGE="${YI_HACK_IMAGE:-borodiliz/yi-hack@sha256:3af230b23f26b0e5ddee942cd6b2a78da5eb7c8c6e8c615e453cd8b806a1b339}"
BASE_SHA_FILE="${BASE_SHA_FILE:-$WORKSPACE/scripts/base-firmware.sha256}"
echo "========================================================================"
echo " Packaging Release Firmware: $CAMERA_MODEL v$OUT_VER (from v$BASE_VER)"
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
if [ ! -d "$WORKSPACE/src/www/_install/www" ]; then
    echo "Compiling WebUI..."
    (cd "$WORKSPACE/src/www" && ./compile.www)
fi
mkdir -p "$FS_DIR/yi-hack/www"
cp -rf "$WORKSPACE/src/www/_install/www/"* "$FS_DIR/yi-hack/www/"

cp -f "$WORKSPACE/src/rRTSPServer/_install/bin/rRTSPServer" "$FS_DIR/yi-hack/bin/rRTSPServer"
cp -f "$WORKSPACE/src/h264grabber/_install/bin/h264grabber" "$FS_DIR/yi-hack/bin/h264grabber"
ln -sf /home/yi-hack/bin/h264grabber "$FS_DIR/yi-hack/bin/h264grabber_h"
ln -sf /home/yi-hack/bin/h264grabber "$FS_DIR/yi-hack/bin/h264grabber_l"
cp -f "$WORKSPACE/src/static/static/home/yi-hack/script/wd.sh" "$FS_DIR/yi-hack/script/wd.sh"
cp -rf "$WORKSPACE/src/static/static/home/yi-hack/script/mqtt_advertise/"* "$FS_DIR/yi-hack/script/mqtt_advertise/"
echo "$OUT_VER" > "$FS_DIR/yi-hack/version"

echo "5. Re-packing JFFS2 home partition with mkfs.jffs2..."
docker run --rm --platform linux/amd64 \
  --entrypoint bash \
  -v "$WORKSPACE:/workspace" \
  -w /workspace \
  "$YI_HACK_IMAGE" \
  -c "mkfs.jffs2 -l -e 0x10000 -r /workspace/.fw_build_${CAMERA_MODEL}/extracted/fs_1 -o /workspace/.fw_build_${CAMERA_MODEL}/home_${CAMERA_MODEL} && chmod -R 777 /workspace/.fw_build_${CAMERA_MODEL}"

echo "6. Creating release distribution archive..."
OUT_TGZ="$WORKSPACE/out/${CAMERA_MODEL}_${OUT_VER}.tgz"
(
  cd "$WORK_DIR"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}" > SHA256SUMS
  else
    shasum -a 256 "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}" > SHA256SUMS
  fi
  tar -zcvf "$OUT_TGZ" "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}" SHA256SUMS
)

rm -rf "$WORK_DIR"
echo "========================================================================"
echo " SUCCESS: Generated $OUT_TGZ"
echo " Size: $(ls -lh "$OUT_TGZ" | awk '{print $5}')"
echo "========================================================================"
