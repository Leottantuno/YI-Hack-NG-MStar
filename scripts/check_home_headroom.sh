#!/bin/sh
# Verify /home headroom after pack (local report) or on-camera (df).
#
# Usage:
#   scripts/check_home_headroom.sh report [model] [version] [profile]
#   scripts/check_home_headroom.sh cam [host]
#
# Target: >= 2.5 MiB free on /home after flash (2560 KiB).

set -e
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TARGET_KIB="${HOME_HEADROOM_TARGET_KIB:-2560}"

MODE="${1:-report}"

case "$MODE" in
    report)
        MODEL="${2:-y203c}"
        VER="${3:-$(cat "$ROOT/VERSION")}"
        PROFILE="${4:-slim}"
        REPORT="$ROOT/out/${MODEL}_${VER}-${PROFILE}.headroom.txt"
        if [ ! -f "$REPORT" ]; then
            echo "Missing $REPORT — run PACK_PROFILE=$PROFILE ./scripts/pack_release.sh $MODEL $VER first" >&2
            exit 1
        fi
        echo "=== Headroom report: $REPORT ==="
        cat "$REPORT"
        EST=$(awk -F= '/^est_free_bytes=/{print $2}' "$REPORT")
        EST_KIB=$((EST / 1024))
        echo "Estimated free: ${EST_KIB} KiB (target >= ${TARGET_KIB} KiB)"
        if [ "$EST_KIB" -ge "$TARGET_KIB" ]; then
            echo "PASS"
            exit 0
        fi
        echo "FAIL: below target"
        exit 2
        ;;
    cam)
        HOST="${2:-}"
        if [ -z "$HOST" ]; then
            # shellcheck disable=SC1091
            . "$ROOT/scripts/cam_env.sh"
            HOST="$CAM_HOST"
        fi
        echo "=== On-camera /home df ($HOST) ==="
        OUT=$(
          "$ROOT/scripts/cam_ssh.sh" --host "$HOST" \
            'df -k /home; echo ---; du -sk /home/yi-hack /home/app /home/base /home/lib /home/ms 2>/dev/null; echo ---; echo VER=$(cat /home/yi-hack/version 2>/dev/null); echo PROFILE=$(cat /home/yi-hack/pack_profile 2>/dev/null || echo none); echo FREE_K=$(df -k /home | awk "NR==2{print \$4}")'
        )
        printf '%s\n' "$OUT"
        FREE_K=$(printf '%s\n' "$OUT" | sed -n 's/^FREE_K=//p' | tr -d '\r' | tail -1)
        echo "Free KiB: ${FREE_K:-?} (target >= $TARGET_KIB)"
        case "$FREE_K" in
            ''|*[!0-9]*)
                echo "FAIL: could not parse free space"
                exit 2
                ;;
        esac
        if [ "$FREE_K" -ge "$TARGET_KIB" ]; then
            echo "PASS"
            exit 0
        fi
        echo "FAIL: below target (flash slim image to reclaim)"
        exit 2
        ;;
    *)
        echo "usage: $0 report [model] [version] [profile] | cam [host]" >&2
        exit 2
        ;;
esac
