#!/bin/sh

# Emit a JS assignment; strip anything outside a conservative hostname charset
# so a crafted /etc/hostname cannot break out of the string literal.
HN=$(cat /etc/hostname 2>/dev/null | tr -cd 'A-Za-z0-9._-')
[ -n "$HN" ] || HN="yi-hack"

printf "Content-type: text/javascript\r\n\r\n"
printf 'hostname="%s";\n' "$HN"
