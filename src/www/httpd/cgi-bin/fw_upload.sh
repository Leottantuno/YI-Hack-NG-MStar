#!/bin/sh

export PATH=$PATH:/home/base/tools:/home/yi-hack/bin:/home/yi-hack/sbin:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/lib:/home/yi-hack/lib:/tmp/sd/yi-hack/lib

YI_HACK_PREFIX="/home/yi-hack"
FW_DIR="/tmp/sd/.fw_upgrade"
MIN_FW_BYTES=2000000

. $YI_HACK_PREFIX/www/cgi-bin/fw_common.sh

json_err() {
    CODE="$1"
    MSG="$2"
    printf "Status: %s\r\n" "$CODE"
    printf "Content-type: application/json\r\n\r\n"
    printf '{"error": true, "message": "%s"}\n' "$MSG"
    exit 0
}

# 0. Require httpd Basic Auth (REMOTE_USER is set only after successful auth)
if [ -z "$REMOTE_USER" ]; then
    json_err "401 Unauthorized" "Authentication required for firmware upload."
fi

# 1. Check if SD card is mounted
FREE_SD=$(df /tmp/sd/ 2>/dev/null | grep -E 'mmc|sd' | awk '{print $4}')
if [ -z "$FREE_SD" ]; then
    json_err "400 Bad Request" "No SD card detected. SD card is required for firmware upgrade."
fi

# 2. Check free space on SD card (require at least 40MB)
if [ "$FREE_SD" -lt 40000 ]; then
    json_err "400 Bad Request" "Insufficient SD card space (at least 40MB required)."
fi

# 3. Clean and prepare upgrade directory on SD
rm -rf "$FW_DIR"
mkdir -p "$FW_DIR"
UPLOAD_FILE="$FW_DIR/manual_upload.tgz"

# 4. Stream stdin into upload file
cat > "$UPLOAD_FILE"

MODEL_SUFFIX=$(cat $YI_HACK_PREFIX/model_suffix 2>/dev/null)

# 5–10. Shared validate / extract / stage / backup
if ! fw_stage_from_archive "manual_upload.tgz" "$MODEL_SUFFIX"; then
    rm -rf "$FW_DIR"
    json_err "400 Bad Request" "Firmware staging failed: ${FW_STAGE_ERR:-unknown}."
fi

# 11. Return success response to the browser
printf "Content-type: application/json\r\n\r\n"
printf '{"error": false, "message": "Firmware validated successfully. Camera is rebooting to flash..."}\n'

# 12. Asynchronously flush, terminate httpd and reboot
sync
sync
sync
(sleep 2 && killall httpd && sleep 1 && reboot -f) </dev/null >/dev/null 2>&1 &
