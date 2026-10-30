#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"

CONFIG_SET="script/mqtt_advertise/mqtt_adv_config.sh"
CONF_FILE="etc/camera.conf"
CONF_MQTT_ADVERTISE_FILE="etc/mqtt_advertise.conf"
MQTT_FILE="etc/mqttv4.conf"

PATH=$PATH:$YI_HACK_PREFIX/bin:$YI_HACK_PREFIX/usr/bin
LD_LIBRARY_PATH=$YI_HACK_PREFIX/lib:$LD_LIBRARY_PATH

get_config() {
    key=^$1
    grep -w $key $YI_HACK_PREFIX/$MQTT_FILE | cut -d "=" -f2-
}

get_mqtt_advertise_config() {
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CONF_MQTT_ADVERTISE_FILE | cut -d "=" -f2-
}

MQTT_IP=$(get_config MQTT_IP)
MQTT_PORT=$(get_config MQTT_PORT)
MQTT_USER=$(get_config MQTT_USER)
MQTT_PASSWORD=$(get_config MQTT_PASSWORD)

HOST=$MQTT_IP
if [ ! -z $MQTT_PORT ]; then
    HOST=$HOST' -p '$MQTT_PORT
fi
if [ ! -z $MQTT_USER ]; then
    HOST=$HOST' -u '$MQTT_USER' -P '$MQTT_PASSWORD
fi

MQTT_PREFIX=$(get_config MQTT_PREFIX)
MQTT_ADV_CAMERA_SETTING_TOPIC=$(get_mqtt_advertise_config MQTT_ADV_CAMERA_SETTING_TOPIC)
[ -z "$MQTT_ADV_CAMERA_SETTING_TOPIC" ] && MQTT_ADV_CAMERA_SETTING_TOPIC="camera_setting"

TOPIC_SET=$MQTT_PREFIX'/'$MQTT_ADV_CAMERA_SETTING_TOPIC'/+/set'
TOPIC_CMD=$MQTT_PREFIX'/command/+'

while :; do
$YI_HACK_PREFIX/bin/mosquitto_sub -v -h $HOST -t $TOPIC_SET -t $TOPIC_CMD | while read -r SUBSCRIBED; do
    FULL_TOPIC=$(echo "$SUBSCRIBED" | awk '{print $1}')
    VAL=$(echo "$SUBSCRIBED" | cut -d' ' -f2-)
    [ -z "$FULL_TOPIC" ] && continue

    # Check for Action Commands
    case "$FULL_TOPIC" in
        */command/reboot)
            sync
            sync
            sync
            (sleep 1 && reboot -f) &
            continue
        ;;
        */command/restart_rtsp)
            $YI_HACK_PREFIX/script/service.sh rtsp restart &
            continue
        ;;
        */command/snapshot)
            MODEL_SUF=$(cat $YI_HACK_PREFIX/model_suffix 2>/dev/null)
            SNAP_TOPIC=$(get_config TOPIC_MOTION_IMAGE)
            [ -z "$SNAP_TOPIC" ] && SNAP_TOPIC="motion_detection_image"
            imggrabber -m "$MODEL_SUF" -r high > /tmp/ha_snap.jpg 2>/dev/null
            if [ -f /tmp/ha_snap.jpg ]; then
                $YI_HACK_PREFIX/bin/mosquitto_pub -h $HOST -t "$MQTT_PREFIX/$SNAP_TOPIC" -f /tmp/ha_snap.jpg
                rm -f /tmp/ha_snap.jpg
            fi &
            continue
        ;;
    esac

    # Camera Settings Configuration
    CONF_UPPER=$(echo "$FULL_TOPIC" | awk -F / '{ print $(NF-1)}')
    CONF=$(echo "$CONF_UPPER" | awk '{ print tolower($0) }')

    sed -i "s/^\(${CONF_UPPER}\s*=\s*\).*$/\1${VAL}/" $YI_HACK_PREFIX/$CONF_FILE
    IPC_OPT=""
    case "$CONF" in
        switch_on)
            IPC_OPT="-t"
        ;;
        save_video_on_motion)
            IPC_OPT="-v"
            if [ "$VAL" = "no" ] || [ "$VAL" = "off" ] ; then
                VAL="always"
            else
                VAL="detect"
            fi
        ;;
        baby_crying_detect)
            IPC_OPT="-b"
        ;;
        sound_detection)
            IPC_OPT="-b"
        ;;
        led)
            IPC_OPT="-l"
        ;;
        ir)
            IPC_OPT="-i"
        ;;
        rotate)
            IPC_OPT="-r"
        ;;
        ptz_preset)
            IPC_OPT="-p"
        ;;
    esac
    if [ "$VAL" = "no" ] || [ "$VAL" = "off" ] ; then
        VAL="off"
    elif [ "$VAL" = "yes" ] || [ "$VAL" = "on" ] ; then
        VAL="on"
    fi
    ipc_cmd $IPC_OPT $VAL &

    $YI_HACK_PREFIX/$CONFIG_SET
done

# program exited, wait and retry
sleep 4
done
