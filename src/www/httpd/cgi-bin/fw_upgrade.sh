#!/bin/sh

export PATH=$PATH:/home/base/tools:/home/yi-hack/bin:/home/yi-hack/sbin:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/home/lib:/home/yi-hack/lib:/tmp/sd/yi-hack/lib

YI_HACK_PREFIX="/home/yi-hack"
FW_DIR="/tmp/sd/.fw_upgrade"
FW_STATUS="$FW_DIR/status"
REPO="Leottantuno/YI-Hack-NG-MStar"
MIN_FW_BYTES=2000000

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh
. $YI_HACK_PREFIX/www/cgi-bin/fw_common.sh

fail_html() {
    printf "Content-type: text/html\r\n\r\n"
    printf "%s" "$1"
    exit
}

write_status() {
    echo "$1" > "$FW_STATUS"
}

# Apply an already-downloaded archive in $FW_DIR/$1
apply_firmware_archive() {
    ARCHIVE="$1"
    MODEL_SUFFIX="$2"

    if fw_stage_from_archive "$ARCHIVE" "$MODEL_SUFFIX"; then
        write_status "rebooting"
        sync; sync; sync
        (sleep 1; killall httpd; sleep 1; reboot -f) </dev/null >/dev/null 2>&1 &
        return 0
    fi
    write_status "error: ${FW_STAGE_ERR:-staging failed}"
    return 1
}

# Background worker: download from GitHub then apply
download_and_apply() {
    MODEL_SUFFIX="$1"
    LATEST_FW="$2"
    CLEAN_LATEST=$(echo "$LATEST_FW" | sed 's/^v//')
    ARCHIVE="${MODEL_SUFFIX}_${CLEAN_LATEST}.tgz"
    URL1="https://github.com/${REPO}/releases/download/${LATEST_FW}/${MODEL_SUFFIX}_${CLEAN_LATEST}.tgz"
    URL2="https://github.com/${REPO}/releases/download/${LATEST_FW}/${MODEL_SUFFIX}_${LATEST_FW}.tgz"

    mkdir -p "$FW_DIR"
    cd "$FW_DIR" || exit 1
    write_status "downloading"

    # Busybox wget follows redirects; use long timeout and resume if possible
    rm -f "$ARCHIVE"
    if ! wget -T 120 -O "$ARCHIVE" "$URL1"; then
        rm -f "$ARCHIVE"
        if ! wget -T 120 -O "$ARCHIVE" "$URL2"; then
            write_status "error: unable to download firmware"
            exit 1
        fi
    fi

    write_status "verifying"
    apply_firmware_archive "$ARCHIVE" "$MODEL_SUFFIX"
}

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

NAME="$(echo $QUERY_STRING | cut -d'=' -f1)"
VAL="$(echo $QUERY_STRING | cut -d'=' -f2)"

if [ "$NAME" != "get" ] ; then
    exit
fi

if [ "$VAL" == "info" ] ; then
    printf "Content-type: application/json\r\n\r\n"

    MODEL_SUFFIX=`cat $YI_HACK_PREFIX/model_suffix`
    FW_VERSION=`cat $YI_HACK_PREFIX/version`
    LATEST_FW=$(fetch_latest_release_tag "$REPO")
    if [ -f /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz ]; then
        LOCAL_FW="true"
    else
        LOCAL_FW="false"
    fi

    printf "{\n"
    printf "\"%s\":\"%s\",\n" "error" "false"
    printf "\"%s\":\"%s\",\n" "fw_version"      "$(fw_json_escape "$FW_VERSION")"
    printf "\"%s\":\"%s\",\n" "latest_fw"       "$(fw_json_escape "$LATEST_FW")"
    printf "\"%s\":%s\n" "local_fw"             "$LOCAL_FW"
    printf "}"

elif [ "$VAL" == "status" ] ; then
    printf "Content-type: application/json\r\n\r\n"
    if [ -f "$FW_STATUS" ]; then
        ST=$(cat "$FW_STATUS")
    else
        ST="idle"
    fi
    # JSON-escape minimal
    ST=$(echo "$ST" | sed 's/"/\\"/g')
    printf "{\"error\":false,\"status\":\"%s\"}\n" "$ST"

elif [ "$VAL" == "upgrade" ] ; then

    FREE_SD=$(df /tmp/sd/ 2>/dev/null | grep -E 'mmc|sd' | awk '{print $4}')
    if [ -z "$FREE_SD" ]; then
        fail_html "No SD detected."
    fi

    if [ "$FREE_SD" -lt 100000 ]; then
        fail_html "No space left on SD."
    fi

    # Avoid overlapping upgrades
    if [ -f "$FW_STATUS" ]; then
        CUR=$(cat "$FW_STATUS")
        case "$CUR" in
            downloading|verifying|rebooting)
                fail_html "Upgrade already in progress ($CUR)."
                ;;
        esac
    fi

    rm -rf "$FW_DIR"
    mkdir -p "$FW_DIR"

    MODEL_SUFFIX=`cat $YI_HACK_PREFIX/model_suffix`
    FW_VERSION=`cat $YI_HACK_PREFIX/version`

    if [ -f /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz ]; then
        mv /tmp/sd/${MODEL_SUFFIX}_x.x.x.tgz "$FW_DIR/${MODEL_SUFFIX}_x.x.x.tgz"
        write_status "verifying"
        if apply_firmware_archive "${MODEL_SUFFIX}_x.x.x.tgz" "$MODEL_SUFFIX"; then
            printf "Content-type: text/html\r\n\r\n"
            printf "Local firmware staged, rebooting and upgrading."
        else
            fail_html "$(cat "$FW_STATUS" 2>/dev/null || echo 'Local firmware invalid.')"
        fi
        exit
    fi

    LATEST_FW=$(fetch_latest_release_tag "$REPO")
    if [ -z "$LATEST_FW" ]; then
        fail_html "Unable to query GitHub releases."
    fi
    CLEAN_LATEST=$(echo "$LATEST_FW" | sed 's/^v//')
    CLEAN_CURRENT=$(echo "$FW_VERSION" | sed 's/^v//')
    if [ "$CLEAN_CURRENT" = "$CLEAN_LATEST" ]; then
        fail_html "No new firmware available."
    fi

    write_status "starting"
    # Download in background so the HTTP request does not time out mid-transfer
    (
        download_and_apply "$MODEL_SUFFIX" "$LATEST_FW"
    ) </dev/null >/tmp/sd/.fw_upgrade/upgrade.log 2>&1 &

    printf "Content-type: text/html\r\n\r\n"
    printf "Firmware download started in background. Keep this page open; the camera will reboot when ready."
fi
