#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"
CAMERA_CONF_FILE="$YI_HACK_PREFIX/etc/camera.conf"
MQTT_CONF_FILE="$YI_HACK_PREFIX/etc/mqttv4.conf"

# Parse mqtt config without sourcing (values may contain shell metacharacters)
get_mqtt() {
    grep -w "$1" "$MQTT_CONF_FILE" | cut -d "=" -f2-
}

MQTT_IP=$(get_mqtt MQTT_IP)
MQTT_PORT=$(get_mqtt MQTT_PORT)
MQTT_USER=$(get_mqtt MQTT_USER)
MQTT_PASSWORD=$(get_mqtt MQTT_PASSWORD)
MQTT_PREFIX=$(get_mqtt MQTT_PREFIX)

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
