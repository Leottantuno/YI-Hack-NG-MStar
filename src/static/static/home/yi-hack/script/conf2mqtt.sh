#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"
CAMERA_CONF_FILE="$YI_HACK_PREFIX/etc/camera.conf"

. $YI_HACK_PREFIX/script/common.sh

MQTT_IP=$(get_mqtt_config MQTT_IP)
MQTT_PORT=$(get_mqtt_config MQTT_PORT)
MQTT_USER=$(get_mqtt_config MQTT_USER)
MQTT_PASSWORD=$(get_mqtt_config MQTT_PASSWORD)
MQTT_PREFIX=$(get_mqtt_config MQTT_PREFIX)

if [ -z "$MQTT_IP" ]; then
    exit
fi
if [ -z "$MQTT_PORT" ]; then
    exit
fi

USER_ARGS=""
PASS_ARGS=""
if [ -n "$MQTT_USER" ]; then
    USER_ARGS="-u $MQTT_USER"
fi
if [ -n "$MQTT_PASSWORD" ]; then
    PASS_ARGS="-P $MQTT_PASSWORD"
fi

while IFS='=' read -r key val ; do
    [ -z "$key" ] && continue
    case "$key" in
        \#*) continue ;;
    esac
    lkey="$(echo "$key" | tr '[A-Z]' '[a-z]')"
    $YI_HACK_PREFIX/bin/mosquitto_pub -h "$MQTT_IP" -p "$MQTT_PORT" $USER_ARGS $PASS_ARGS \
        -t "$MQTT_PREFIX/stat/camera/$lkey" -m "$val" -r
done < "$CAMERA_CONF_FILE"
