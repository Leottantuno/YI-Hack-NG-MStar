#!/bin/sh
# Shared helpers for yi-hack boot/service scripts (and selected CGI that source this).

: "${YI_HACK_PREFIX:=/home/yi-hack}"
: "${CONF_FILE:=etc/system.conf}"
: "${MQTT_CONF_FILE:=etc/mqttv4.conf}"

get_config()
{
    key=$1
    grep -w "$1" "$YI_HACK_PREFIX/$CONF_FILE" | cut -d "=" -f2-
}

get_mqtt_config()
{
    key=$1
    grep -w "$1" "$YI_HACK_PREFIX/$MQTT_CONF_FILE" | cut -d "=" -f2-
}

log()
{
    if [ "$DEBUG_LOG" = "yes" ]; then
        echo "$1" >> /tmp/sd/hack_debug.log

        if [ "$2" = "1" ]; then
            echo "" >> /tmp/sd/hack_debug.log
            ps >> /tmp/sd/hack_debug.log
            echo "" >> /tmp/sd/hack_debug.log
            free >> /tmp/sd/hack_debug.log
            echo "" >> /tmp/sd/hack_debug.log
        fi
    fi
}

# Populate USERNAME/PASSWORD and related auth strings from system.conf.
# Sets: USERNAME, PASSWORD, RTSP_USERPWD, ONVIF_USERPWD, HTTPD_AUTH_READY
load_web_credentials()
{
    USERNAME=$(get_config USERNAME)
    PASSWORD=$(get_config PASSWORD)
    RTSP_USERPWD=""
    ONVIF_USERPWD=""
    HTTPD_AUTH_READY=no

    if [ -n "$USERNAME" ]; then
        RTSP_USERPWD="$USERNAME:$PASSWORD@"
        ONVIF_USERPWD="user=$USERNAME\npassword=$PASSWORD"
        HTTPD_AUTH_READY=yes
    fi
}

# Require both USERNAME and PASSWORD for RTSP/ONVIF auth flags.
# Sets: RTSP_AUTH_OK, RTSP_USER, RTSP_PASSWORD (daemon CLI args)
setup_rtsp_auth_args()
{
    RTSP_AUTH_OK=yes
    RTSP_USER=""
    RTSP_PASSWORD=""

    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        RTSP_USER="-u $USERNAME"
        RTSP_PASSWORD="-w $PASSWORD"
    elif [ -n "$USERNAME" ] || [ -n "$PASSWORD" ]; then
        echo "RTSP: USERNAME/PASSWORD incomplete — refusing to start RTSP unauthenticated" >&2
        RTSP_AUTH_OK=no
    fi
}

httpd_auth_ready()
{
    [ "$HTTPD_AUTH_READY" = "yes" ]
}

# Parse numeric port from config with fallback.
get_port_config()
{
    key=$1
    default=$2
    val=$(get_config "$key")
    case "$val" in
        ''|*[!0-9]*) echo "$default" ;;
        *) echo "$val" ;;
    esac
}
