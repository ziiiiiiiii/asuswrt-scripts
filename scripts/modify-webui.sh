#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Apply tweaks to the WebUI dynamically
#

#jacklul-asuswrt-scripts-update
#shellcheck disable=SC2155,SC2016

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

TWEAKS="cpu_temperature" # list of tweaks to apply
TMP_WWW_PATH="/tmp/$SCRIPT_NAME/www"

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

[ -f "/usr/sbin/helper.sh" ] && MERLIN="1"

# these two sed_* functions are taken/based on https://github.com/RMerl/asuswrt-merlin.ng/blob/master/release/src/router/others/helper.sh
sed_quote() {
    printf "%s\n" "$1" | sed 's/[]\/$*.^&[]/\\&/g'
}

sed_and_check() {
    _MD5SUM="$(md5sum "$4" | awk '{print $1}')"

    PATTERN=$(sed_quote "$2")
    CONTENT=$(sed_quote "$3")

    case "$1" in
        "replace")
            sed -i "s/$PATTERN/$CONTENT/" "$4"
        ;;
        "before")
            sed -i "/$PATTERN/i$CONTENT" "$4"
        ;;
        "after")
            sed -i "/$PATTERN/a$CONTENT" "$4"
        ;;
        *)
            echo "Invalid mode: $1"
            return
        ;;
    esac

    _MD5SUM2="$(md5sum "$4" | awk '{print $1}')"

    if [ "$_MD5SUM" != "$_MD5SUM2" ]; then
        return 0
    fi

    logger -st "$SCRIPT_TAG" "Failed to apply modification to $(basename "$4"): sed $1  \"$2\"  \"$3\""

    return 1
}

cpu_temperature() {
    case "$1" in
        "set")
            if ! mount | grep -q /www/cpu_ram_status.asp; then
                [ ! -f "$TMP_WWW_PATH/cpu_ram_status.asp" ] && cp -f /www/cpu_ram_status.asp "$TMP_WWW_PATH/cpu_ram_status.asp"

                echo "cpuTemp = '<%get_cpu_temperature();%>';" >> "$TMP_WWW_PATH/cpu_ram_status.asp"

                mount --bind "$TMP_WWW_PATH/cpu_ram_status.asp" /www/cpu_ram_status.asp
            fi

            if ! mount | grep -q /www/device-map/router_status.asp; then
                mkdir -p "$TMP_WWW_PATH/device-map"
                [ ! -f "$TMP_WWW_PATH/device-map/router_status.asp" ] && cp -f /www/device-map/router_status.asp "$TMP_WWW_PATH/device-map/router_status.asp"

                sed_and_check replace 'render_CPU(cpuInfo);' 'render_CPU(cpuInfo, cpuTemp);' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed_and_check replace 'function(cpu_info_new)' 'function(cpu_info_new, cpu_temp_new)' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed_and_check after 'Object.keys(cpu_info_new).length;' '$("#cpu_temp").html(parseFloat(cpu_temp_new).toFixed(1));' "$TMP_WWW_PATH/device-map/router_status.asp"
                sed_and_check before "('#cpu_field').html(code);" "code += '<div class=\"info-block\">CPU Temperature: <span id=\"cpu_temp\"></span> °C</div>';" "$TMP_WWW_PATH/device-map/router_status.asp"

                mount --bind "$TMP_WWW_PATH/device-map/router_status.asp" /www/device-map/router_status.asp
            fi
        ;;
        "unset")
            if mount | grep -q /www/cpu_ram_status.asp; then
                umount /www/cpu_ram_status.asp
                rm -f "$TMP_WWW_PATH/cpu_ram_status.asp"
            fi

            if mount | grep -q /www/device-map/router_status.asp; then
                umount /www/device-map/router_status.asp
                rm -f "$TMP_WWW_PATH/device-map/router_status.asp"
            fi
        ;;
    esac
}

www_override() {
    case "$1" in
        "set")
            mkdir -p "$TMP_WWW_PATH"

            logger -st "$SCRIPT_TAG" "Applying WebUI tweaks: $TWEAKS"

            for TWEAK in $TWEAKS; do
                $TWEAK set
            done
        ;;
        "unset")
            logger -st "$SCRIPT_TAG" "Removing WebUI tweaks..."

            cpu_temperature unset

            rm -fr "$TMP_WWW_PATH"
        ;;
    esac
}

case "$1" in
    "start")
        www_override set
    ;;
    "stop")
        www_override unset
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 start|stop|restart"
        exit 1
    ;;
esac
