#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"

validateTarget() {
    case "$1" in
        ''|*[!a-zA-Z0-9.-]* ) return 1 ;;
        * ) return 0 ;;
    esac
}

ACTION="netinfo"
TARGET=""

OLD_IFS="$IFS"
IFS='&'
for PAIR in $QUERY_STRING; do
    IFS="$OLD_IFS"
    [ -z "$PAIR" ] && continue
    CONF="${PAIR%%=*}"
    VAL="${PAIR#*=}"
    if [ "$CONF" = "action" ]; then
        ACTION="$VAL"
    elif [ "$CONF" = "target" ]; then
        TARGET="$VAL"
    fi
done

if [ "$ACTION" = "ping" ]; then
    if [ -z "$TARGET" ] || ! validateTarget "$TARGET" || [ ${#TARGET} -gt 64 ]; then
        printf "Content-type: application/json\r\n\r\n"
        printf '{"error":"true","message":"Invalid host or IP"}\n'
        exit
    fi
    PING_RAW=$(ping -c 3 -W 2 "$TARGET" 2>&1)
    LOSS=$(echo "$PING_RAW" | awk -F, '/packet loss/ {for(i=1;i<=NF;i++) if($i~/loss/) print $i}' | sed 's/^ *//')
    RTT=$(echo "$PING_RAW" | awk -F= '/min\/avg\/max/ {print $2}' | sed 's/^ *//')
    OUTPUT_ESC=$(echo "$PING_RAW" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')

    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"error\":\"false\",\n"
    printf "\"target\":\"%s\",\n" "$TARGET"
    printf "\"loss\":\"%s\",\n" "$LOSS"
    printf "\"rtt\":\"%s\",\n" "$RTT"
    printf "\"output\":\"%s\"\n" "$OUTPUT_ESC"
    printf "}\n"
    exit
fi

if [ "$ACTION" = "netinfo" ]; then
    GW=$(route -n | awk '$1=="0.0.0.0" {print $2; exit}')
    DNS=$(awk '/nameserver/ {print $2}' /etc/resolv.conf 2>/dev/null | tr '\n' ' ' | sed 's/ $//')
    SSID=$(wpa_cli status 2>/dev/null | awk -F= '$1=="ssid" {print $2; exit}')
    BSSID=$(wpa_cli status 2>/dev/null | awk -F= '$1=="bssid" {print $2; exit}')
    SIGNAL=$(wpa_cli status 2>/dev/null | awk -F= '$1=="signal_level" {print $2; exit}')
    LINK=$(awk '/wlan0/ {gsub(/\./, ""); print $3}' /proc/net/wireless 2>/dev/null)
    IP=$(ifconfig wlan0 2>/dev/null | awk '/inet addr/{print substr($2,6)}')
    MASK=$(ifconfig wlan0 2>/dev/null | awk '/Mask/{print substr($4,6)}')
    MAC=$(cat /sys/class/net/wlan0/address 2>/dev/null)

    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"error\":\"false\",\n"
    printf "\"gateway\":\"%s\",\n" "$GW"
    printf "\"dns\":\"%s\",\n" "$DNS"
    printf "\"ssid\":\"%s\",\n" "$SSID"
    printf "\"bssid\":\"%s\",\n" "$BSSID"
    printf "\"signal_level\":\"%s\",\n" "$SIGNAL"
    printf "\"link_quality\":\"%s\",\n" "$LINK"
    printf "\"ip\":\"%s\",\n" "$IP"
    printf "\"netmask\":\"%s\",\n" "$MASK"
    printf "\"mac\":\"%s\"\n" "$MAC"
    printf "}\n"
    exit
fi

printf "Content-type: application/json\r\n\r\n"
printf '{"error":"true","message":"Unknown action"}\n'
