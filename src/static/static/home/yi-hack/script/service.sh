#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"

. $YI_HACK_PREFIX/script/common.sh

YI_HACK_VER=$(cat /home/yi-hack/version)
MODEL_SUFFIX=$(cat /home/yi-hack/model_suffix)
if [[ $MODEL_SUFFIX == "y23" ]]; then
    SERIAL_NUMBER=$(dd status=none bs=1 count=20 skip=592 if=/tmp/mmap.info | tr '\0' '0' | cut -c1-20)
else
    SERIAL_NUMBER=$(dd status=none bs=1 count=20 skip=661 if=/tmp/mmap.info | tr '\0' '0' | cut -c1-20)
fi
HW_ID=$(dd status=none bs=1 count=4 skip=661 if=/tmp/mmap.info | tr '\0' '0' | cut -c1-4)

init_config()
{
    if [ -f $YI_HACK_PREFIX/etc/TZ ]; then
        TZ_TMP=`cat $YI_HACK_PREFIX/etc/TZ`
    fi

    load_web_credentials
    if [ -n "$USERNAME" ] && [ -z "$PASSWORD" ]; then
        echo "USERNAME set but PASSWORD empty — ONVIF/RTSP auth incomplete" >&2
        RTSP_AUTH_OK=no
    else
        RTSP_AUTH_OK=yes
    fi

    RTSP_PORT=$(get_port_config RTSP_PORT 554)
    HTTPD_PORT=$(get_port_config HTTPD_PORT 80)

    D_RTSP_PORT=""
    D_HTTPD_PORT=""
    if [[ $RTSP_PORT != "554" ]] ; then
        D_RTSP_PORT=:$RTSP_PORT
    fi
    if [[ $HTTPD_PORT != "80" ]] ; then
        D_HTTPD_PORT=:$HTTPD_PORT
    fi

    if [[ $(get_config RTSP) == "yes" ]] ; then
        if [[ $(get_config RTSP_ALT) == "alternative" ]] ; then
            RTSP_DAEMON="rtsp_server_yi"
        elif [[ $(get_config RTSP_ALT) == "go2rtc" ]] ; then
            RTSP_DAEMON="go2rtc"
            if [ ! -f /tmp/sd/yi-hack/bin/go2rtc ]; then
                RTSP_DAEMON="rRTSPServer"
            fi
        else
            RTSP_DAEMON="rRTSPServer"
        fi

        RTSP_AUDIO=$(get_config RTSP_AUDIO)
        NR_LEVEL=$(get_config RTSP_AUDIO_NR_LEVEL)
        if [ "$RTSP_AUDIO" == "aac" ]; then
            if [[ $(get_config RTSP_ALT) == "alternative" ]] ; then
                # alternative is not able to convert PCM to AAC
                RTSP_AUDIO="alaw"
                ONVIF_AUDIO_ENCODER="audio_encoder=alaw"
                NR_LEVEL=""
            else
                ONVIF_AUDIO_ENCODER="audio_encoder=aac"
            fi
            HG2_AUDIO="-a"
        elif [ "$RTSP_AUDIO" == "pcm" ]; then
            ONVIF_AUDIO_ENCODER="audio_encoder=none"
        elif [ "$RTSP_AUDIO" == "none" ] || [ "$RTSP_AUDIO" == "no" ] ; then
            RTSP_AUDIO="no"
            ONVIF_AUDIO_ENCODER="audio_encoder=none"
        else
            ONVIF_AUDIO_ENCODER="audio_encoder=$RTSP_AUDIO"
        fi
        if [ ! -z $RTSP_AUDIO ]; then
            RTSP_AUDIO_OPTION="-a "$RTSP_AUDIO
        fi
        if [ ! -z $RTSP_PORT ]; then
            P_RTSP_PORT="-p "$RTSP_PORT
        fi
        # Require both credentials for RTSP auth; never pass only one (fail-open).
        setup_rtsp_auth_args
        if [ ! -z $NR_LEVEL ]; then
            NR_LEVEL="-n "$NR_LEVEL
        fi

        RTSP_RES=$(get_config RTSP_STREAM)
        RTSP_ALT=$(get_config RTSP_ALT)
    fi

    ONVIF_AUDIO_BC=$(get_config ONVIF_AUDIO_BC)
    if [ ! -z $ONVIF_AUDIO_BC ]; then
        ONVIF_AUDIO_DECODER="audio_decoder=$ONVIF_AUDIO_BC"
        if [ "$ONVIF_AUDIO_BC" != "NONE" ] && [ "$ONVIF_AUDIO_BC" != "none" ]; then
            if [ "$ONVIF_AUDIO_BC" == "G711" ]; then
                RTSP_AUDIO_BC="-b ulaw"
            else
                RTSP_AUDIO_BC="-b $ONVIF_AUDIO_BC"
            fi
        fi
    else
        ONVIF_AUDIO_BC="none"
        ONVIF_AUDIO_DECODER="audio_decoder=$ONVIF_AUDIO_BC"
    fi
    if [[ $(get_config ONVIF_ENABLE_MEDIA2) == "yes" ]] ; then
        ONVIF_ENABLE_MEDIA2=1
    else
        ONVIF_ENABLE_MEDIA2=0
    fi
    if [[ $(get_config ONVIF_FAULT_IF_UNKNOWN) == "yes" ]] ; then
        ONVIF_FAULT_IF_UNKNOWN=1
    else
        ONVIF_FAULT_IF_UNKNOWN=0
    fi
    if [[ $(get_config ONVIF_FAULT_IF_SET) == "yes" ]] ; then
        ONVIF_FAULT_IF_SET=1
    else
        ONVIF_FAULT_IF_SET=0
    fi
    if [[ $(get_config ONVIF_SYNOLOGY_NVR) == "yes" ]] ; then
        ONVIF_SYNOLOGY_NVR=1
    else
        ONVIF_SYNOLOGY_NVR=0
    fi
}

start_rtsp_grabbers()
{
    killall -q h264grabber h264grabber_l h264grabber_h 2>/dev/null || true
    case "$RTSP_RES" in
        low)
            h264grabber_l -m $MODEL_SUFFIX -r low -f &
            ;;
        high)
            h264grabber_h -m $MODEL_SUFFIX -r high -f &
            ;;
        both)
            h264grabber_l -m $MODEL_SUFFIX -r low -f &
            h264grabber_h -m $MODEL_SUFFIX -r high -f &
            ;;
    esac
    sleep 1
}

ensure_rtsp_watchdog()
{
    WD_COUNT=$(ps | grep wd.sh | grep -v grep | grep -c ^)
    if [ $WD_COUNT -eq 0 ]; then
        (sleep 30; $YI_HACK_PREFIX/script/wd.sh >/dev/null) &
    fi
}

start_rtsp_go2rtc()
{
    echo "streams:" > /tmp/go2rtc.yaml
    if [ "$RTSP_RES" == "high" ] || [ "$RTSP_RES" == "both" ]; then
        echo "  ch0_0.h264:" >> /tmp/go2rtc.yaml
        echo "    - exec:h264grabber_h -m $MODEL_SUFFIX -r high#backchannel=0" >> /tmp/go2rtc.yaml
    fi
    if [ "$RTSP_RES" == "low" ] || [ "$RTSP_RES" == "both" ]; then
        echo "  ch0_1.h264:" >> /tmp/go2rtc.yaml
        echo "    - exec:h264grabber_l -m $MODEL_SUFFIX -r low#backchannel=0" >> /tmp/go2rtc.yaml
    fi

    echo "" >> /tmp/go2rtc.yaml
    echo "api:" >> /tmp/go2rtc.yaml
    echo "  listen: \"\"" >> /tmp/go2rtc.yaml
    echo "" >> /tmp/go2rtc.yaml
    echo "webrtc:" >> /tmp/go2rtc.yaml
    echo "  listen: \"\"" >> /tmp/go2rtc.yaml
    echo "" >> /tmp/go2rtc.yaml
    echo "rtsp:" >> /tmp/go2rtc.yaml
    echo "  listen: \":$RTSP_PORT\"" >> /tmp/go2rtc.yaml
    if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
        echo "  username: \"$USERNAME\"" >> /tmp/go2rtc.yaml
        echo "  password: \"$PASSWORD\"" >> /tmp/go2rtc.yaml
    fi

    /tmp/sd/yi-hack/bin/go2rtc -c /tmp/go2rtc.yaml -d
}

start_rtsp_alternative()
{
    CODEC_LOW=$(cat /tmp/lowres)
    if [ ! -z $CODEC_LOW ]; then
        CODEC_LOW="-c "$CODEC_LOW
    fi
    CODEC_HIGH=$(cat /tmp/highres)
    if [ ! -z $CODEC_HIGH ]; then
        CODEC_HIGH="-C "$CODEC_HIGH
    fi

    start_rtsp_grabbers
    case "$RTSP_RES" in
        low)
            $RTSP_DAEMON -m $MODEL_SUFFIX -r low $CODEC_LOW $RTSP_AUDIO_OPTION $P_RTSP_PORT $RTSP_USER $RTSP_PASSWORD $RTSP_AUDIO_BC $NR_LEVEL > /dev/null &
            ;;
        high)
            $RTSP_DAEMON -m $MODEL_SUFFIX -r high $CODEC_HIGH $RTSP_AUDIO_OPTION $P_RTSP_PORT $RTSP_USER $RTSP_PASSWORD $RTSP_AUDIO_BC $NR_LEVEL > /dev/null &
            ;;
        both)
            $RTSP_DAEMON -m $MODEL_SUFFIX -r both $CODEC_LOW $CODEC_HIGH $RTSP_AUDIO_OPTION $P_RTSP_PORT $RTSP_USER $RTSP_PASSWORD $RTSP_AUDIO_BC $NR_LEVEL > /dev/null &
            ;;
    esac
    ensure_rtsp_watchdog
}

start_rtsp_standard()
{
    CODEC_LOW="h264"
    CODEC_HIGH="h264"
    if [[ $MODEL_SUFFIX == H305R ]]; then
        CODEC_HIGH="h265"
    fi

    start_rtsp_grabbers
    case "$RTSP_RES" in
        low)
            $RTSP_DAEMON -r low -c $CODEC_LOW $RTSP_AUDIO_OPTION $P_RTSP_PORT $RTSP_USER $RTSP_PASSWORD $RTSP_AUDIO_BC $NR_LEVEL > /dev/null &
            ;;
        high)
            $RTSP_DAEMON -r high -C $CODEC_HIGH $RTSP_AUDIO_OPTION $P_RTSP_PORT $RTSP_USER $RTSP_PASSWORD $RTSP_AUDIO_BC $NR_LEVEL > /dev/null &
            ;;
        both)
            $RTSP_DAEMON -r both -c $CODEC_LOW -C $CODEC_HIGH $RTSP_AUDIO_OPTION $P_RTSP_PORT $RTSP_USER $RTSP_PASSWORD $RTSP_AUDIO_BC $NR_LEVEL > /dev/null &
            ;;
    esac
    ensure_rtsp_watchdog
}

start_rtsp()
{
    if [ "$RTSP_AUTH_OK" = "no" ]; then
        echo "Skipping RTSP start: set both USERNAME and PASSWORD in system.conf" >&2
        return
    fi

    if [ "$1" == "low" ] || [ "$1" == "high" ] || [ "$1" == "both" ]; then
        RTSP_RES=$1
    fi
    if [ "$2" == "no" ] || [ "$2" == "yes" ] || [ "$2" == "alaw" ] || [ "$2" == "ulaw" ] || [ "$2" == "pcm" ] || [ "$2" == "aac" ] ; then
        RTSP_AUDIO=$2
        RTSP_AUDIO_OPTION="-a "$2
    fi

    if [ "$RTSP_ALT" == "go2rtc" ]; then
        start_rtsp_go2rtc
    elif [ "$RTSP_ALT" == "alternative" ]; then
        start_rtsp_alternative
    else
        start_rtsp_standard
    fi
}

stop_rtsp()
{
    killall -q wd.sh 2>/dev/null
    killall -q $RTSP_DAEMON 2>/dev/null
    # Always stop grabbers too — leaving them alive after killing the RTSP
    # daemon leaves FIFO writers without a reader (SIGPIPE/EOF races, issue #597).
    killall -q h264grabber h264grabber_l h264grabber_h h264grabber2 2>/dev/null
    killall -q go2rtc 2>/dev/null
}

onvif_profile_line()
{
    # $1=name $2=width $3=height $4=stream_path $5=snap_res
    echo "name=$1\nwidth=$2\nheight=$3\nurl=rtsp://$RTSP_USERPWD%s$D_RTSP_PORT/$4\nsnapurl=http://$RTSP_USERPWD%s$D_HTTPD_PORT/cgi-bin/snapshot.sh?res=$5$WATERMARK\ntype=H264\n$ONVIF_AUDIO_ENCODER\n$ONVIF_AUDIO_DECODER"
}

start_onvif()
{
    if [[ "$2" == "null" ]]; then
        ONVIF_WM_SNAPSHOT=$(get_config ONVIF_WM_SNAPSHOT)
        WATERMARK="&watermark="$ONVIF_WM_SNAPSHOT
    elif [[ "$2" == "yes" ]]; then
        WATERMARK="&watermark=yes"
    fi
    if [[ "$1" == "null" ]]; then
        ONVIF_PROFILE=$(get_config ONVIF_PROFILE)
    elif [[ "$1" == "low" ]] || [[ "$1" == "high" ]] || [[ "$1" == "both" ]]; then
        ONVIF_PROFILE=$1
    fi

    ONVIF_PROFILE_0=""
    ONVIF_PROFILE_1=""
    if [[ $ONVIF_PROFILE == "high" ]] || [[ $ONVIF_PROFILE == "both" ]]; then
        ONVIF_PROFILE_0=$(onvif_profile_line Profile_0 1920 1080 ch0_0.h264 high)
    fi
    if [[ $ONVIF_PROFILE == "low" ]] || [[ $ONVIF_PROFILE == "both" ]]; then
        ONVIF_PROFILE_1=$(onvif_profile_line Profile_1 640 360 ch0_1.h264 low)
    fi

    ONVIF_SRVD_CONF="/tmp/onvif_simple_server.conf"

    echo "model=Yi Hack" > $ONVIF_SRVD_CONF
    echo "manufacturer=Yi" >> $ONVIF_SRVD_CONF
    echo "firmware_ver=$YI_HACK_VER" >> $ONVIF_SRVD_CONF
    echo "hardware_id=$HW_ID" >> $ONVIF_SRVD_CONF
    echo "serial_num=$SERIAL_NUMBER" >> $ONVIF_SRVD_CONF
    echo "ifs=wlan0" >> $ONVIF_SRVD_CONF
    echo "port=$HTTPD_PORT" >> $ONVIF_SRVD_CONF
    echo "scope=onvif://www.onvif.org/Profile/Streaming" >> $ONVIF_SRVD_CONF
    echo "scope=onvif://www.onvif.org/Profile/T" >> $ONVIF_SRVD_CONF
    echo "scope=onvif://www.onvif.org/hardware" >> $ONVIF_SRVD_CONF
    echo "scope=onvif://www.onvif.org/name" >> $ONVIF_SRVD_CONF
    echo "adv_enable_media2=$ONVIF_ENABLE_MEDIA2" >> $ONVIF_SRVD_CONF
    echo "adv_fault_if_unknown=$ONVIF_FAULT_IF_UNKNOWN" >> $ONVIF_SRVD_CONF
    echo "adv_fault_if_set=$ONVIF_FAULT_IF_SET" >> $ONVIF_SRVD_CONF
    echo "adv_synology_nvr=$ONVIF_SYNOLOGY_NVR" >> $ONVIF_SRVD_CONF
    echo "" >> $ONVIF_SRVD_CONF
    if [ ! -z $ONVIF_USERPWD ]; then
        echo -e $ONVIF_USERPWD >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi
    if [ ! -z $ONVIF_PROFILE_0 ]; then
        echo "#Profile 0" >> $ONVIF_SRVD_CONF
        echo -e $ONVIF_PROFILE_0 >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi
    if [ ! -z $ONVIF_PROFILE_1 ]; then
        echo "#Profile 1" >> $ONVIF_SRVD_CONF
        echo -e $ONVIF_PROFILE_1 >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi

    if [[ $MODEL_SUFFIX == "h201c" ]] || [[ $MODEL_SUFFIX == "h305r" ]] || [[ $MODEL_SUFFIX == "y30" ]] || [[ $MODEL_SUFFIX == "h307" ]] ; then
        echo "#PTZ" >> $ONVIF_SRVD_CONF
        echo "ptz=1" >> $ONVIF_SRVD_CONF
        echo "zoom=0" >> $ONVIF_SRVD_CONF
        echo "max_step_x=360" >> $ONVIF_SRVD_CONF
        echo "max_step_y=180" >> $ONVIF_SRVD_CONF
        echo "get_position=/home/yi-hack/bin/ipc_cmd -g" >> $ONVIF_SRVD_CONF
        echo "is_moving=/home/yi-hack/bin/ipc_cmd -u" >> $ONVIF_SRVD_CONF
        echo "move_left=/home/yi-hack/bin/ipc_cmd -m left" >> $ONVIF_SRVD_CONF
        echo "move_right=/home/yi-hack/bin/ipc_cmd -m right" >> $ONVIF_SRVD_CONF
        echo "move_up=/home/yi-hack/bin/ipc_cmd -m up" >> $ONVIF_SRVD_CONF
        echo "move_down=/home/yi-hack/bin/ipc_cmd -m down" >> $ONVIF_SRVD_CONF
        echo "move_stop=/home/yi-hack/bin/ipc_cmd -m stop" >> $ONVIF_SRVD_CONF
        echo "move_preset=/home/yi-hack/bin/ipc_cmd -p %d" >> $ONVIF_SRVD_CONF
        echo "goto_home_position=/home/yi-hack/bin/ipc_cmd -p 0" >> $ONVIF_SRVD_CONF
        echo "set_preset=/home/yi-hack/script/ptz_presets.sh -a add_preset -n %d -m %s" >> $ONVIF_SRVD_CONF
        echo "set_home_position=/home/yi-hack/script/ptz_presets.sh -a set_home_position" >> $ONVIF_SRVD_CONF
        echo "remove_preset=/home/yi-hack/script/ptz_presets.sh -a del_preset -n %d" >> $ONVIF_SRVD_CONF
        echo "jump_to_abs=/home/yi-hack/bin/ipc_cmd -j %f,%f" >> $ONVIF_SRVD_CONF
        echo "jump_to_rel=/home/yi-hack/bin/ipc_cmd -J %f,%f" >> $ONVIF_SRVD_CONF
        echo "get_presets=/home/yi-hack/script/ptz_presets.sh -a get_presets" >> $ONVIF_SRVD_CONF
        echo "" >> $ONVIF_SRVD_CONF
    fi

    echo "#EVENT" >> $ONVIF_SRVD_CONF
    echo "events=3" >> $ONVIF_SRVD_CONF
    echo "#Event 0" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:VideoSource/MotionAlarm" >> $ONVIF_SRVD_CONF
    echo "source_name=Source" >> $ONVIF_SRVD_CONF
    echo "source_type=tt:ReferenceToken" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/motion_alarm" >> $ONVIF_SRVD_CONF
    echo "#Event 1" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/PeopleDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_type=xsd:string" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/human_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 2" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/VehicleDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_type=xsd:string" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/vehicle_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 3" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/DogCatDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_type=xsd:string" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/animal_detection" >> $ONVIF_SRVD_CONF
    echo "#Event 4" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:RuleEngine/MyRuleDetector/BabyCryingDetect" >> $ONVIF_SRVD_CONF
    echo "source_name=VideoSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_type=xsd:string" >> $ONVIF_SRVD_CONF
    echo "source_value=VideoSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/baby_crying" >> $ONVIF_SRVD_CONF
    echo "#Event 5" >> $ONVIF_SRVD_CONF
    echo "topic=tns1:AudioAnalytics/Audio/DetectedSound" >> $ONVIF_SRVD_CONF
    echo "source_name=AudioSourceConfigurationToken" >> $ONVIF_SRVD_CONF
    echo "source_type=tt:ReferenceToken" >> $ONVIF_SRVD_CONF
    echo "source_value=AudioSourceToken" >> $ONVIF_SRVD_CONF
    echo "input_file=/tmp/onvif_notify_server/sound_detection" >> $ONVIF_SRVD_CONF

    chmod 0600 $ONVIF_SRVD_CONF
    ipc2file
    mkdir -p /tmp/onvif_notify_server
    onvif_notify_server --conf_file $ONVIF_SRVD_CONF
}

stop_onvif()
{
    killall onvif_notify_server
    killall ipc2file
    killall onvif_simple_server
}

start_wsdd()
{
    wsd_simple_server --pid_file /var/run/wsd_simple_server.pid --if_name wlan0 --xaddr "http://%s$D_HTTPD_PORT/onvif/device_service" -m `hostname` -n Yi
}

stop_wsdd()
{
    killall wsd_simple_server
}

ftpd_daemon_name()
{
    if [[ "$1" == "null" ]] ; then
        if [[ $(get_config BUSYBOX_FTPD) == "yes" ]] ; then
            echo "busybox"
        else
            echo "pure-ftpd"
        fi
    else
        echo "$1"
    fi
}

start_ftpd()
{
    FTPD_DAEMON=$(ftpd_daemon_name "$1")

    if [[ $FTPD_DAEMON == "busybox" ]] ; then
        tcpsvd -vE 0.0.0.0 21 ftpd -w >/dev/null &
    elif [[ $FTPD_DAEMON == "pure-ftpd" ]] ; then
        pure-ftpd -B
    fi
}

stop_ftpd()
{
    FTPD_DAEMON=$(ftpd_daemon_name "$1")

    if [[ $FTPD_DAEMON == "busybox" ]] ; then
        killall tcpsvd
    elif [[ $FTPD_DAEMON == "pure-ftpd" ]] ; then
        killall pure-ftpd
    fi
}

start_mp4record_svc()
{
    cd /home/app
    if [[ $(get_config TIME_OSD) == "yes" ]] ; then
        TZP=`TZ=$TZ_TMP date +%z`
        TZP=${TZP:0:3}:${TZP:3:2}
        TZ=GMT$TZP ./mp4record > /dev/null &
    else
        ./mp4record > /dev/null &
    fi
}

ps_program()
{
    PS_PROGRAM=$(ps | grep $1 | grep -v grep | grep -c ^)
    if [ $PS_PROGRAM -gt 0 ]; then
        echo "started"
    else
        echo "stopped"
    fi
}

NAME="null"
ACTION="null"
PARAM1="null"
PARAM2="null"
RES=""

if [ $# -lt 2 ]; then
    exit
fi

NAME=$1
ACTION=$2
if [ $# -eq 3 ]; then
    PARAM1=$3
fi
if [ $# -eq 4 ]; then
    PARAM2=$4
fi

init_config

if [ "$ACTION" == "start" ] ; then
    if [ "$NAME" == "rtsp" ]; then
        start_rtsp $PARAM1 $PARAM2
    elif [ "$NAME" == "onvif" ]; then
        start_onvif $PARAM1 $PARAM2
    elif [ "$NAME" == "wsdd" ]; then
        start_wsdd
    elif [ "$NAME" == "ftpd" ]; then
        start_ftpd $PARAM1
    elif [ "$NAME" == "mqtt" ]; then
        mqttv4 > /dev/null &
    elif [ "$NAME" == "mqtt-config" ]; then
        mqtt-config > /dev/null &
    elif [ "$NAME" == "mp4record" ]; then
        start_mp4record_svc
    elif [ "$NAME" == "all" ]; then
        start_rtsp
        start_onvif
        start_wsdd
        start_ftpd
        mqttv4 > /dev/null &
        mqtt-config > /dev/null &
        start_mp4record_svc
    fi
elif [ "$ACTION" == "stop" ] ; then
    if [ "$NAME" == "rtsp" ]; then
        stop_rtsp
    elif [ "$NAME" == "onvif" ]; then
        stop_onvif
    elif [ "$NAME" == "wsdd" ]; then
        stop_wsdd
    elif [ "$NAME" == "ftpd" ]; then
        stop_ftpd $PARAM1
    elif [ "$NAME" == "mqtt-config" ]; then
        killall mqtt-config
    elif [ "$NAME" == "mqtt" ]; then
        killall mqttv4
    elif [ "$NAME" == "mp4record" ]; then
        killall mp4record
    elif [ "$NAME" == "all" ]; then
        stop_rtsp
        stop_onvif
        stop_wsdd
        stop_ftpd
        killall mqtt-config
        killall mqttv4
        killall mp4record
    fi
elif [ "$ACTION" == "status" ] ; then
    if [ "$NAME" == "rtsp" ]; then
        RES=$(ps_program rRTSPServer)
    elif [ "$NAME" == "onvif" ]; then
        RES=$(ps_program onvif_notify_server)
    elif [ "$NAME" == "wsdd" ]; then
        RES=$(ps_program wsd_simple_server)
    elif [ "$NAME" == "ftpd" ]; then
        RES=$(ps_program ftpd)
    elif [ "$NAME" == "mqtt" ]; then
        RES=$(ps_program mqttv4)
    elif [ "$NAME" == "mqtt-config" ]; then
        RES=$(ps_program mqtt-config)
    elif [ "$NAME" == "mp4record" ]; then
        RES=$(ps_program mp4record)
    elif [ "$NAME" == "all" ]; then
        RES=$(ps_program rRTSPServer)
    fi
fi

if [ ! -z $RES ]; then
    echo $RES
fi
