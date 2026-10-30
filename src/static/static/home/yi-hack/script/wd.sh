#!/bin/sh

CONF_FILE="etc/system.conf"
CAMERA_CONF_FILE="etc/camera.conf"

YI_HACK_PREFIX="/home/yi-hack"
MODEL_SUFFIX=$(cat /home/yi-hack/model_suffix)

START_STOP_SCRIPT=$YI_HACK_PREFIX/script/service.sh

#LOG_FILE="/tmp/sd/wd.log"
LOG_FILE="/dev/null"
LOGWIFI_FILE="/tmp/sd/hack_wififailsafe.log"

FAILSAFE_WIFI=0
COUNTER_H=0
COUNTER_L=0
COUNTER_LIMIT=10
INTERVAL=10

get_camera_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CAMERA_CONF_FILE | cut -d "=" -f2-
}

get_config()
{
    key=$1
    grep -w $1 $YI_HACK_PREFIX/$CONF_FILE | cut -d "=" -f2-
}

restart_rtsp()
{
    $START_STOP_SCRIPT rtsp start
}

is_running()
{
    ps | grep -v grep | grep -q "$1"
}

check_rtsp()
{
    if [ "$(get_camera_config SWITCH_ON)" = "yes" ] ; then
        LISTEN=$(netstat -an 2>&1 | grep ":$RTSP_PORT_NUMBER " | grep LISTEN | grep -c ^)
        if [ "$LISTEN" -eq 0 ]; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') - RTSP port $RTSP_PORT_NUMBER not listening, restarting..." >> $LOG_FILE
            killall -q rRTSPServer
            killall -q h264grabber h264grabber_l h264grabber_h
            sleep 1
            restart_rtsp
            return
        fi

        STREAM_CONF=$(get_config RTSP_STREAM)
        if [ "$STREAM_CONF" = "low" ] || [ "$STREAM_CONF" = "both" ]; then
            if ! is_running "h264grabber_l" || ! is_running "rRTSPServer"; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Missing processes for low res, restarting..." >> $LOG_FILE
                killall -q rRTSPServer
                killall -q h264grabber h264grabber_l h264grabber_h
                sleep 1
                restart_rtsp
                return
            fi
        fi

        if [ "$STREAM_CONF" = "high" ] || [ "$STREAM_CONF" = "both" ]; then
            if ! is_running "h264grabber_h" || ! is_running "rRTSPServer"; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Missing processes for high res, restarting..." >> $LOG_FILE
                killall -q rRTSPServer
                killall -q h264grabber h264grabber_l h264grabber_h
                sleep 1
                restart_rtsp
                return
            fi
        fi
    else
        echo "Camera is swiched off no rtsp restart needed" >> $LOG_FILE
    fi
}

check_rtsp_alt()
{
    if [ "$(get_camera_config SWITCH_ON)" = "yes" ] ; then
        LISTEN=$(netstat -an 2>&1 | grep ":$RTSP_PORT_NUMBER " | grep LISTEN | grep -c ^)
        if [ "$LISTEN" -eq 0 ]; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') - RTSP alt port not listening, restarting..." >> $LOG_FILE
            killall -q rtsp_server_yi
            killall -q h264grabber h264grabber_l h264grabber_h
            sleep 1
            restart_rtsp
            return
        fi

        STREAM_CONF=$(get_config RTSP_STREAM)
        if [ "$STREAM_CONF" = "low" ] || [ "$STREAM_CONF" = "both" ]; then
            if ! is_running "h264grabber_l" || ! is_running "rtsp_server_yi"; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Missing processes for low res (alt), restarting..." >> $LOG_FILE
                killall -q rtsp_server_yi
                killall -q h264grabber h264grabber_l h264grabber_h
                sleep 1
                restart_rtsp
                return
            fi
        fi

        if [ "$STREAM_CONF" = "high" ] || [ "$STREAM_CONF" = "both" ]; then
            if ! is_running "h264grabber_h" || ! is_running "rtsp_server_yi"; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Missing processes for high res (alt), restarting..." >> $LOG_FILE
                killall -q rtsp_server_yi
                killall -q h264grabber h264grabber_l h264grabber_h
                sleep 1
                restart_rtsp
                return
            fi
        fi
    else
        echo "Camera is swiched off no rtsp restart needed" >> $LOG_FILE
    fi
}

check_rtsp_go2rtc()
{
    if [ "$(get_camera_config SWITCH_ON)" = "yes" ] ; then
        LISTEN=$(netstat -an 2>&1 | grep ":$RTSP_PORT_NUMBER " | grep LISTEN | grep -c ^)
        if [ "$LISTEN" -eq 0 ]; then
            echo "$(date +'%Y-%m-%d %H:%M:%S') - go2rtc port not listening, restarting..." >> $LOG_FILE
            killall -q go2rtc
            killall -q h264grabber h264grabber_l h264grabber_h
            sleep 1
            restart_rtsp
            return
        fi

        STREAM_CONF=$(get_config RTSP_STREAM)
        if [ "$STREAM_CONF" = "low" ] || [ "$STREAM_CONF" = "both" ]; then
            if ! is_running "h264grabber_l" || ! is_running "go2rtc"; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Missing processes for low res (go2rtc), restarting..." >> $LOG_FILE
                killall -q go2rtc
                killall -q h264grabber h264grabber_l h264grabber_h
                sleep 1
                restart_rtsp
                return
            fi
        fi

        if [ "$STREAM_CONF" = "high" ] || [ "$STREAM_CONF" = "both" ]; then
            if ! is_running "h264grabber_h" || ! is_running "go2rtc"; then
                echo "$(date +'%Y-%m-%d %H:%M:%S') - Missing processes for high res (go2rtc), restarting..." >> $LOG_FILE
                killall -q go2rtc
                killall -q h264grabber h264grabber_l h264grabber_h
                sleep 1
                restart_rtsp
                return
            fi
        fi
    else
        echo "Camera is swiched off no rtsp restart needed" >> $LOG_FILE
    fi
}

check_rmm()
{
#  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking rmm process..." >> $LOG_FILE
    PS=`ps | grep rmm | grep -v grep | grep -c ^`

    if [ $PS -eq 0 ]; then
        echo "check_rmm failed, reboot!" >> $LOG_FILE
        sync
        reboot -f
    fi
}

check_mqtt()
{
#  echo "$(date +'%Y-%m-%d %H:%M:%S') - Checking mqttv4 process..." >> $LOG_FILE
    PS=`ps ww | grep mqttv4 | grep -v grep | grep -c ^`

    if [ $PS -eq 0 ]; then
        echo "check_mqtt failed, restart it!" >> $LOG_FILE
        $START_STOP_SCRIPT mqtt start
    fi
}

check_wifi()
{
    WPA_OK=0
    if wpa_cli -i wlan0 status 2>&1 | grep -q "wpa_state=COMPLETED"; then
        WPA_OK=1
    fi

    GATEWAY_OK=0
    GW=$(route -n 2>/dev/null | awk '$1 == "0.0.0.0" {print $2; exit}')
    if [ -n "$GW" ] && [ "$GW" != "0.0.0.0" ]; then
        if ping -c 1 -W 2 "$GW" >/dev/null 2>&1; then
            GATEWAY_OK=1
        fi
    fi

    if [ "$WPA_OK" -eq 1 ] && [ "$GATEWAY_OK" -eq 1 ]; then
        FAILSAFE_WIFI=0
        return
    fi

    FAILSAFE_WIFI=$((FAILSAFE_WIFI + 1))
    echo "$(date +'%Y-%m-%d %H:%M:%S') - WiFi issue (wpa_ok=$WPA_OK, gw_ok=$GATEWAY_OK, fail_count=$FAILSAFE_WIFI)" >> "$LOGWIFI_FILE"

    if [ "$FAILSAFE_WIFI" -lt 3 ]; then
        # Stage 1: Soft wpa reassociate/reconfigure (non-disruptive)
        wpa_cli -i wlan0 reassociate >/dev/null 2>&1 || wpa_cli -i wlan0 reconfigure >/dev/null 2>&1
    elif [ "$FAILSAFE_WIFI" -lt 6 ]; then
        # Stage 2: Cycle interface and refresh DHCP lease
        ifconfig wlan0 down
        sleep 1
        ifconfig wlan0 up
        sleep 1
        wpa_cli -i wlan0 reassociate >/dev/null 2>&1
        $YI_HACK_PREFIX/script/wifidhcp.sh >/dev/null 2>&1 &
    elif [ "$FAILSAFE_WIFI" -lt 10 ]; then
        # Stage 3: Full wpa_supplicant restart
        killall -q wpa_supplicant
        sleep 1
        /home/base/tools/wpa_supplicant -c/tmp/wpa_supplicant.conf -g/var/run/wpa_supplicant-global -Dnl80211 -iwlan0 -B
        sleep 2
        $YI_HACK_PREFIX/script/wifidhcp.sh >/dev/null 2>&1 &
    else
        # Stage 4: Persistent failure after ~100s without network, reboot system safely
        echo "$(date +'%Y-%m-%d %H:%M:%S') - WiFi recovery failed after $FAILSAFE_WIFI attempts. Rebooting..." >> "$LOGWIFI_FILE"
        sync
        reboot -f
    fi
}

if [[ $(get_config RTSP) == "no" ]] ; then
    exit
fi

case $(get_config RTSP_PORT) in
    ''|*[!0-9]*) RTSP_PORT=554 ;;
    *) RTSP_PORT=$(get_config RTSP_PORT) ;;
esac

if [ ! -z $RTSP_PORT ]; then
    RTSP_PORT_NUMBER=$RTSP_PORT
fi

RTSP_ALT=$(get_config RTSP_ALT)

echo "$(date +'%Y-%m-%d %H:%M:%S') - Starting RTSP watchdog..." >> $LOG_FILE

while true
do
    if [ "$RTSP_ALT" = "alternative" ]; then
        check_rtsp_alt
    elif [ "$RTSP_ALT" = "go2rtc" ]; then
        check_rtsp_go2rtc
    else
        check_rtsp
    fi
    check_rmm
    check_mqtt
    check_wifi

    echo 1500 > /sys/class/net/eth0/mtu 2>/dev/null
    echo 1500 > /sys/class/net/wlan0/mtu 2>/dev/null

    if [ "$COUNTER_H" -eq 0 ] && [ "$COUNTER_L" -eq 0 ]; then
        sleep "$INTERVAL"
    fi
done
