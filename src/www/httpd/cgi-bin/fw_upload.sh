#!/bin/sh

export PATH=$PATH:/home/base/tools:/home/yi-hack/bin:/home/yi-hack/sbin:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/lib:/home/yi-hack/lib:/tmp/sd/yi-hack/lib

YI_HACK_PREFIX="/home/yi-hack"

# 1. Check if SD card is mounted
FREE_SD=$(df /tmp/sd/ 2>/dev/null | grep -E 'mmc|sd' | awk '{print $4}')
if [ -z "$FREE_SD" ]; then
    printf "Status: 400 Bad Request\r\n"
    printf "Content-type: application/json\r\n\r\n"
    printf '{"error": true, "message": "No SD card detected. SD card is required for firmware upgrade."}\n'
    exit 0
fi

# 2. Check free space on SD card (require at least 40MB)
if [ "$FREE_SD" -lt 40000 ]; then
    printf "Status: 400 Bad Request\r\n"
    printf "Content-type: application/json\r\n\r\n"
    printf '{"error": true, "message": "Insufficient SD card space (at least 40MB required)."}\n'
    exit 0
fi

# 3. Clean and prepare upgrade directory on SD
rm -rf /tmp/sd/.fw_upgrade
mkdir -p /tmp/sd/.fw_upgrade
UPLOAD_FILE="/tmp/sd/.fw_upgrade/manual_upload.tgz"

# 4. Stream stdin into upload file
cat > "$UPLOAD_FILE"

# 5. Validate file exists and size is reasonable (> 2MB)
FILE_SIZE=$(ls -l "$UPLOAD_FILE" 2>/dev/null | awk '{print $5}')
if [ -z "$FILE_SIZE" ] || [ "$FILE_SIZE" -lt 2000000 ]; then
    rm -rf /tmp/sd/.fw_upgrade
    printf "Status: 400 Bad Request\r\n"
    printf "Content-type: application/json\r\n\r\n"
    printf '{"error": true, "message": "Uploaded archive is invalid or empty."}\n'
    exit 0
fi

cd /tmp/sd/.fw_upgrade

# 6. Verify tar archive integrity
if ! tar -ztf manual_upload.tgz >/dev/null 2>&1; then
    cd /
    rm -rf /tmp/sd/.fw_upgrade
    printf "Status: 400 Bad Request\r\n"
    printf "Content-type: application/json\r\n\r\n"
    printf '{"error": true, "message": "Archive corrupted or not a valid gzip tarball."}\n'
    exit 0
fi

# 7. Check camera model compatibility
MODEL_SUFFIX=$(cat $YI_HACK_PREFIX/model_suffix 2>/dev/null)
if [ -n "$MODEL_SUFFIX" ]; then
    HAS_SYS=$(tar -ztf manual_upload.tgz 2>/dev/null | grep -E "(^|/)sys_${MODEL_SUFFIX}$")
    HAS_HOME=$(tar -ztf manual_upload.tgz 2>/dev/null | grep -E "(^|/)home_${MODEL_SUFFIX}$")
    if [ -z "$HAS_SYS" ] || [ -z "$HAS_HOME" ]; then
        cd /
        rm -rf /tmp/sd/.fw_upgrade
        printf "Status: 400 Bad Request\r\n"
        printf "Content-type: application/json\r\n\r\n"
        printf '{"error": true, "message": "Model mismatch! Archive does not match camera model ('"$MODEL_SUFFIX"')."}\n'
        exit 0
    fi
fi

# 8. Extract the archive
tar -zxvf manual_upload.tgz >/dev/null 2>&1
rm -f manual_upload.tgz

# 9. Move partitions to the SD root (/tmp/sd/) where MStar bootloader expects them
mv -f sys_* home_* .. 2>/dev/null

# 10. Backup configuration to /tmp/sd/.fw_upgrade/ for system.sh to restore upon first boot
cp -f $YI_HACK_PREFIX/etc/*.conf . 2>/dev/null
[ -f $YI_HACK_PREFIX/etc/hostname ] && cp -f $YI_HACK_PREFIX/etc/hostname .
[ -f $YI_HACK_PREFIX/etc/TZ ] && cp -f $YI_HACK_PREFIX/etc/TZ .
[ -f $YI_HACK_PREFIX/etc/passwd ] && cp -f $YI_HACK_PREFIX/etc/passwd .
touch $YI_HACK_PREFIX/.fw_upgrade_in_progress

# 11. Return success response to the browser
printf "Content-type: application/json\r\n\r\n"
printf '{"error": false, "message": "Firmware validated successfully. Camera is rebooting to flash..."}\n'

# 12. Asynchronously flush, terminate httpd and reboot
sync
sync
sync
(sleep 2 && killall httpd && sleep 1 && reboot -f) </dev/null >/dev/null 2>&1 &
