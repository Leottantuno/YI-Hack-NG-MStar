#!/bin/bash
set -e

# Usage: ./scripts/pack_release.sh <CAMERA_MODEL> <OUT_VERSION> [BASE_VERSION]
# Example: ./scripts/pack_release.sh y203c 0.6.0 0.5.8

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
CAMERA_MODEL="${1:-y203c}"
OUT_VER="${2:-$(cat "$WORKSPACE/VERSION")}"
BASE_VER="${3:-0.5.8}"
echo "========================================================================"
echo " Packaging Release Firmware: $CAMERA_MODEL v$OUT_VER (from v$BASE_VER)"
echo "========================================================================"

WORK_DIR="$WORKSPACE/.fw_build_$CAMERA_MODEL"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$WORKSPACE/out"

echo "1. Downloading base release archive ($BASE_VER)..."
curl -fsSL -o "$WORK_DIR/base.tgz" "https://github.com/roleoroleo/yi-hack-MStar/releases/download/${BASE_VER}/${CAMERA_MODEL}_${BASE_VER}.tgz"

echo "2. Extracting partitions..."
tar -zxvf "$WORK_DIR/base.tgz" -C "$WORK_DIR"

echo "3. Extracting home JFFS2 partition via jefferson inside container..."
docker run --rm --platform linux/amd64 \
  --entrypoint bash \
  -v "$WORKSPACE:/workspace" \
  -w /workspace \
  borodiliz/yi-hack:latest \
  -c "python /usr/local/bin/jefferson /workspace/.fw_build_${CAMERA_MODEL}/home_${CAMERA_MODEL} -d /workspace/.fw_build_${CAMERA_MODEL}/extracted"

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
  borodiliz/yi-hack:latest \
  -c "mkfs.jffs2 -l -e 0x10000 -r /workspace/.fw_build_${CAMERA_MODEL}/extracted/fs_1 -o /workspace/.fw_build_${CAMERA_MODEL}/home_${CAMERA_MODEL}"

echo "6. Creating release distribution archive..."
OUT_TGZ="$WORKSPACE/out/${CAMERA_MODEL}_${OUT_VER}.tgz"
tar -zcvf "$OUT_TGZ" -C "$WORK_DIR" "sys_${CAMERA_MODEL}" "home_${CAMERA_MODEL}"

rm -rf "$WORK_DIR"
echo "========================================================================"
echo " SUCCESS: Generated $OUT_TGZ"
echo " Size: $(ls -lh "$OUT_TGZ" | awk '{print $5}')"
echo "========================================================================"
