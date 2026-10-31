#!/bin/sh

YI_HACK_PREFIX="/home/yi-hack"

. $YI_HACK_PREFIX/www/cgi-bin/validate.sh

if ! $(validateQueryString $QUERY_STRING); then
    printf "Content-type: application/json\r\n\r\n"
    printf "{\n"
    printf "\"%s\":\"%s\"\\n" "error" "true"
    printf "}"
    exit
fi

MODEL=$(cat /home/yi-hack/model_suffix 2>/dev/null)
RES="-r low"
WATERMARK=""

case "$QUERY_STRING" in
    *res=high*) RES="-r high" ;;
    *res=low*) RES="-r low" ;;
esac
case "$QUERY_STRING" in
    *watermark=yes*) WATERMARK="-w" ;;
esac

BOUNDARY="mjpeg_boundary"

printf "Content-Type: multipart/x-mixed-replace; boundary=%s\r\n" "$BOUNDARY"
printf "Cache-Control: no-cache, no-store, must-revalidate\r\n"
printf "Pragma: no-cache\r\n\r\n"

while :; do
    printf -- "--%s\r\n" "$BOUNDARY"
    printf "Content-Type: image/jpeg\r\n\r\n"
    if ! imggrabber -m "$MODEL" $RES $WATERMARK; then
        break
    fi
    printf "\r\n"
    sleep 0.1
done
