#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

fbasename()
{
    echo ${1:0:$((${#1} - 4))}
}

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
