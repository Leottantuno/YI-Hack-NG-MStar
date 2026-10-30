#!/bin/sh
# SSH/SCP helper using gitignored .env credentials.
# Usage:
#   scripts/cam_ssh.sh [host] 'remote command'
#   scripts/cam_ssh.sh --scp local remote_path
#   scripts/cam_ssh.sh --host 192.168.2.63 'uname -a'

set -e
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$ROOT/scripts/cam_env.sh"

MODE="ssh"
HOST="$CAM_HOST"
while [ $# -gt 0 ]; do
    case "$1" in
        --scp) MODE="scp"; shift ;;
        --host) HOST="$2"; shift 2 ;;
        --) shift; break ;;
        -*) echo "Unknown option: $1" >&2; exit 2 ;;
        *) break ;;
    esac
done

# dropbear on yi-hack: shell login is root; HTTP user is CAM_UN
SSH_USER="${CAM_SSH_USER:-root}"

# Boot scripts export these; bare SSH sessions often do not.
REMOTE_ENV='export PATH=/usr/bin:/usr/sbin:/bin:/sbin:/home/base/tools:/home/yi-hack/bin:/home/yi-hack/sbin:/tmp/sd/yi-hack/bin:/tmp/sd/yi-hack/sbin; export LD_LIBRARY_PATH=/home/ms:/home/lib:/home/yi-hack/lib:/lib:/tmp/sd/yi-hack/lib${LD_LIBRARY_PATH:+:}$LD_LIBRARY_PATH;'

if [ "$MODE" = "scp" ]; then
    LOCAL="$1"
    REMOTE="$2"
    [ -n "$LOCAL" ] && [ -n "$REMOTE" ] || { echo "usage: $0 --scp local remote" >&2; exit 2; }
    export HOST SSH_USER CAM_PW LOCAL REMOTE
    expect << 'EOF'
set timeout 60
spawn scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o PreferredAuthentications=password -o PubkeyAuthentication=no $env(LOCAL) $env(SSH_USER)@$env(HOST):$env(REMOTE)
expect {
  -re "(?i)password:" { send -- "$env(CAM_PW)\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EOF
else
    CMD="$REMOTE_ENV $*"
    [ -n "$*" ] || { echo "usage: $0 [ --host IP ] 'cmd'" >&2; exit 2; }
    export HOST SSH_USER CAM_PW CMD
    expect << 'EOF'
set timeout 60
spawn ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR -o PreferredAuthentications=password -o PubkeyAuthentication=no $env(SSH_USER)@$env(HOST) $env(CMD)
expect {
  -re "(?i)password:" { send -- "$env(CAM_PW)\r"; exp_continue }
  eof
}
catch wait result
exit [lindex $result 3]
EOF
fi
