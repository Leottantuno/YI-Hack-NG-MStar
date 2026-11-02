#!/bin/sh

# Expected: 2024Y01M15D10H/00M00S00.mp4 (27 chars: dir + / + 12-char clip name)
validateRecFile()
{
    case "$1" in
        [0-9][0-9][0-9][0-9]Y[0-9][0-9]M[0-9][0-9]D[0-9][0-9]H/[0-9][0-9]M[0-9][0-9]S[0-9][0-9].mp4)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

fbasename()
{
    echo ${1:0:$((${#1} - 4))}
}

YI_HACK_PREFIX="/home/yi-hack"

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}\n"
    exit
fi

FILE="none"

CONF="$(echo $QUERY_STRING | cut -d'=' -f1)"
VAL="$(echo $QUERY_STRING | cut -d'=' -f2)"

if [ "$CONF" == "file" ] ; then
    FILE="$VAL"
fi

if ! validateRecFile "$FILE"; then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}\n"
    exit
fi

BASE_NAME=$(fbasename "$FILE")
rm -f "/tmp/sd/record/$BASE_NAME.mp4"
rm -f "/tmp/sd/record/$BASE_NAME.jpg"

printf "Content-type: application/json\r\n\r\n"

printf "{\n"
printf "\"%s\":\"%s\"\\n" "error" "false"
printf "}\n"
