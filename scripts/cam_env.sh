#!/bin/sh
# Load camera credentials from repo-root .env (gitignored).
# Usage: . "$(dirname "$0")/cam_env.sh"   OR   source scripts/cam_env.sh

_CAM_ENV_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
_CAM_ENV_FILE="${CAM_ENV_FILE:-$_CAM_ENV_ROOT/.env}"

if [ ! -f "$_CAM_ENV_FILE" ]; then
    echo "Missing $_CAM_ENV_FILE — create a .env file with CAM_UN, CAM_PW, CAM_HOST" >&2
    return 1 2>/dev/null || exit 1
fi

# shellcheck disable=SC1090
set -a
. "$_CAM_ENV_FILE"
set +a

: "${CAM_UN:?CAM_UN not set in .env}"
: "${CAM_PW:?CAM_PW not set in .env}"
CAM_HOST="${CAM_HOST:-192.168.1.100}"

unset _CAM_ENV_ROOT _CAM_ENV_FILE
