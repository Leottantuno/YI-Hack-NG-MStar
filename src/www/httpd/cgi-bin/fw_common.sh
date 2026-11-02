#!/bin/sh
# Shared firmware staging helpers for fw_upgrade.sh / fw_upload.sh.
# Source after setting YI_HACK_PREFIX.

: "${YI_HACK_PREFIX:=/home/yi-hack}"
: "${FW_DIR:=/tmp/sd/.fw_upgrade}"
: "${MIN_FW_BYTES:=2000000}"

# Parse GitHub /releases/latest JSON for tag_name only.
# Do NOT use greedy s/.*"\([^"]*\)"/ — body text steals the last quoted string.
# Avoid head(1): not present on all yi-hack busybox builds.
fetch_latest_release_tag()
{
    REPO_PATH="$1"
    RAW=$(wget -T 20 -O - -U "yi-hack-fw-upgrade" \
        "https://api.github.com/repos/${REPO_PATH}/releases/latest" 2>/dev/null) || RAW=""
    TAG=$(printf '%s\n' "$RAW" | sed -n 's/.*"tag_name":"\([^"]*\)".*/\1/p' | sed -n '1p')
    # Accept only version-like tags (v0.3.1 / 0.3.1)
    case "$TAG" in
        v[0-9]*|[0-9]*[.][0-9]*)
            printf '%s' "$TAG"
            ;;
        *)
            printf ''
            ;;
    esac
}

fw_json_escape()
{
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/'"$(printf '\t')"'/\\t/g' | tr '\n\r' '  '
}

fw_archive_size_ok()
{
    ARCHIVE="$1"
    SIZE=$(ls -l "$ARCHIVE" 2>/dev/null | awk '{print $5}')
    if [ -z "$SIZE" ] || [ "$SIZE" -lt "$MIN_FW_BYTES" ]; then
        return 1
    fi
    return 0
}

fw_archive_tar_ok()
{
    ARCHIVE="$1"
    tar -ztf "$ARCHIVE" >/dev/null 2>&1
}

fw_archive_model_ok()
{
    ARCHIVE="$1"
    MODEL_SUFFIX="$2"
    # If model file missing on device, skip model gate (legacy behaviour)
    if [ -z "$MODEL_SUFFIX" ]; then
        return 0
    fi
    HAS_SYS=$(tar -ztf "$ARCHIVE" 2>/dev/null | grep -E "(^|/)sys_${MODEL_SUFFIX}$")
    HAS_HOME=$(tar -ztf "$ARCHIVE" 2>/dev/null | grep -E "(^|/)home_${MODEL_SUFFIX}$")
    if [ -z "$HAS_SYS" ] || [ -z "$HAS_HOME" ]; then
        return 1
    fi
    return 0
}

# Optional: verify SHA256SUMS in cwd when sha256sum exists
fw_verify_sha256sums()
{
    if [ -f SHA256SUMS ] && command -v sha256sum >/dev/null 2>&1; then
        sha256sum -c SHA256SUMS >/dev/null 2>&1
        return $?
    fi
    return 0
}

fw_backup_config()
{
    DEST="${1:-.}"
    cp -f $YI_HACK_PREFIX/etc/*.conf "$DEST" 2>/dev/null
    [ -f $YI_HACK_PREFIX/etc/hostname ] && cp -f $YI_HACK_PREFIX/etc/hostname "$DEST"
    [ -f $YI_HACK_PREFIX/etc/TZ ] && cp -f $YI_HACK_PREFIX/etc/TZ "$DEST"
    [ -f $YI_HACK_PREFIX/etc/passwd ] && cp -f $YI_HACK_PREFIX/etc/passwd "$DEST"
    touch $YI_HACK_PREFIX/.fw_upgrade_in_progress
}

# Extract archive in $FW_DIR, verify, move partitions to /tmp/sd/, backup conf.
# On failure prints nothing; caller uses status helpers.
# Returns 0 on success. Sets FW_STAGE_ERR on failure.
fw_stage_from_archive()
{
    ARCHIVE="$1"
    MODEL_SUFFIX="$2"
    FW_STAGE_ERR=""

    if [ ! -f "$FW_DIR/$ARCHIVE" ]; then
        FW_STAGE_ERR="archive missing"
        return 1
    fi

    if ! fw_archive_size_ok "$FW_DIR/$ARCHIVE"; then
        SIZE=$(ls -l "$FW_DIR/$ARCHIVE" 2>/dev/null | awk '{print $5}')
        FW_STAGE_ERR="download incomplete (${SIZE:-0} bytes)"
        return 1
    fi

    if ! fw_archive_tar_ok "$FW_DIR/$ARCHIVE"; then
        FW_STAGE_ERR="archive corrupted"
        return 1
    fi

    if ! fw_archive_model_ok "$FW_DIR/$ARCHIVE" "$MODEL_SUFFIX"; then
        FW_STAGE_ERR="model mismatch (need sys_${MODEL_SUFFIX} and home_${MODEL_SUFFIX})"
        return 1
    fi

    cd "$FW_DIR" || {
        FW_STAGE_ERR="cannot enter FW_DIR"
        return 1
    }

    if ! tar -zxvf "$ARCHIVE" >/dev/null 2>&1; then
        FW_STAGE_ERR="extract failed"
        return 1
    fi
    rm -f "$ARCHIVE"

    if ! fw_verify_sha256sums; then
        FW_STAGE_ERR="SHA256SUMS mismatch"
        return 1
    fi

    if ! mv -f sys_* home_* /tmp/sd/ 2>/dev/null; then
        FW_STAGE_ERR="could not stage partitions on SD"
        return 1
    fi

    fw_backup_config "$FW_DIR"
    return 0
}
