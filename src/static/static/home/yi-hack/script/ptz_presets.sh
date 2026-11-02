#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"
PTZ_CONF_FILE=$YI_HACK_PREFIX/etc/ptz_presets.conf

# Avoid eval: assign PRESET_N via case only.
set_preset() {
    _idx="$1"
    _val="$2"
    case "$_idx" in
        0) PRESET_0="$_val" ;;
        1) PRESET_1="$_val" ;;
        2) PRESET_2="$_val" ;;
        3) PRESET_3="$_val" ;;
        4) PRESET_4="$_val" ;;
        5) PRESET_5="$_val" ;;
        6) PRESET_6="$_val" ;;
        7) PRESET_7="$_val" ;;
    esac
}

get_preset() {
    case "$1" in
        0) echo "$PRESET_0" ;;
        1) echo "$PRESET_1" ;;
        2) echo "$PRESET_2" ;;
        3) echo "$PRESET_3" ;;
        4) echo "$PRESET_4" ;;
        5) echo "$PRESET_5" ;;
        6) echo "$PRESET_6" ;;
        7) echo "$PRESET_7" ;;
    esac
}

# Preset names: letters, digits, underscore, hyphen, space only.
validate_preset_name() {
    case "$1" in
        ''|*[!A-Za-z0-9_\ \-]*) return 1 ;;
        *) return 0 ;;
    esac
}

validate_coord() {
    case "$1" in
        ''|*[!0-9\-]*) return 1 ;;
        *) return 0 ;;
    esac
}

edit_preset() {
    FIRST_AVAIL=8
    PRESET_0=""
    PRESET_1=""
    PRESET_2=""
    PRESET_3=""
    PRESET_4=""
    PRESET_5=""
    PRESET_6=""
    PRESET_7=""

    OLD_IFS="$IFS"
    IFS="=,"
    while read -r PNUM PNAME PX PY; do
        if [ -z "$PNUM" ]; then
            continue
        fi
        if [ "${PNUM#\#}" != "$PNUM" ]; then
            continue
        fi
        if [ -z "$PNAME" ] && [ "$FIRST_AVAIL" -gt "$PNUM" ] 2>/dev/null; then
            FIRST_AVAIL=$PNUM
        fi
        if [ "$1" = "add" ] && [ "$PNAME" = "$2" ]; then
            IFS="$OLD_IFS"
            return 1
        fi

        for I in 0 1 2 3 4 5 6 7; do
            if [ "$PNUM" = "$I" ]; then
                set_preset "$I" "$PNAME,$PX,$PY"
            fi
        done
    done < "$PTZ_CONF_FILE"

    IFS="$OLD_IFS"

    if [ "$1" = "add" ]; then
        if ! validate_preset_name "$2"; then
            return 3
        fi
        # Coords may be empty for set_home_position; otherwise must be numeric
        if [ -n "$3" ] || [ -n "$4" ]; then
            if ! validate_coord "$3" || ! validate_coord "$4"; then
                return 3
            fi
        fi
        if [ "$FIRST_AVAIL" -le 7 ]; then
            set_preset "$FIRST_AVAIL" "$2,$3,$4"
        else
            return 2
        fi
    fi

    if [ "$1" = "del" ]; then
        for I in 0 1 2 3 4 5 6 7; do
            if [ "$2" = "$I" ] || [ "$2" = "all" ]; then
                set_preset "$I" ""
            fi
        done
    fi

    if [ "$1" = "edit" ]; then
        if ! validate_preset_name "$3"; then
            return 3
        fi
        if ! validate_coord "$4" || ! validate_coord "$5"; then
            return 3
        fi
        for I in 0 1 2 3 4 5 6 7; do
            if [ "$2" = "$I" ]; then
                set_preset "$I" "$3,$4,$5"
            fi
        done
    fi

    if [ "$1" = "add" ] || [ "$1" = "del" ] || [ "$1" = "edit" ]; then
        {
            echo "0=$(get_preset 0)"
            echo "1=$(get_preset 1)"
            echo "2=$(get_preset 2)"
            echo "3=$(get_preset 3)"
            echo "4=$(get_preset 4)"
            echo "5=$(get_preset 5)"
            echo "6=$(get_preset 6)"
            echo "7=$(get_preset 7)"
        } > "$PTZ_CONF_FILE"
    fi
}

ACTION="none"
NUM=-1
NAME=""

while [ $# -gt 0 ]; do
  case $1 in
    -a|--action)
      ACTION="$2"
      shift
      shift
      ;;
    -n|--number)
      NUM="$2"
      shift
      shift
      ;;
    -m|--name)
      NAME="$2"
      shift
      shift
      ;;
    -*|--*)
      echo "Unknown option $1"
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$ACTION" = "get_presets" ] ; then
    cat "$PTZ_CONF_FILE"
elif [ "$ACTION" = "go_preset" ] ; then
    if [ "$NUM" -lt 0 ] || [ "$NUM" -gt 7 ] ; then
        echo "Preset number out of range"
        exit
    fi
    ipc_cmd -p "$NUM"
elif [ "$ACTION" = "add_preset" ]; then
    POS=$(ipc_cmd -g)
    if [ -z "$POS" ]; then
        echo "Error getting PTZ position"
        exit
    fi
    POSX=$(echo "$POS" | cut -d ',' -f 1)
    POSY=$(echo "$POS" | cut -d ',' -f 2)
    if [ -z "$POSX" ] || [ -z "$POSY" ]; then
        echo "Error getting PTZ position"
        exit
    fi

    if [ "$NUM" = "-1" ]; then
        edit_preset add "$NAME" "$POSX" "$POSY"
    else
        edit_preset edit "$NUM" "$NAME" "$POSX" "$POSY"
    fi

    RES=$?
    if [ "$RES" -eq 1 ]; then
        echo "Preset already exists"
        exit
    fi
    if [ "$RES" -eq 2 ]; then
        echo "No free preset available"
        exit
    fi
    if [ "$RES" -eq 3 ]; then
        echo "Invalid preset name or coordinates"
        exit
    fi
    ipc_cmd -P "$NAME"
elif [ "$ACTION" = "del_preset" ]; then
    edit_preset del "$NUM"
    ipc_cmd -R "$NUM"
elif [ "$ACTION" = "set_home_position" ]; then
    edit_preset del 0
    edit_preset add "Home"
    ipc_cmd -H
else
    echo "Invalid action received"
    exit
fi
