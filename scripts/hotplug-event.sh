#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Handle hotplug events
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

EXECUTE_COMMAND="" # command to execute in addition to build-in script (receives arguments: $1 = subsystem, $2 = action)

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

hotplug_config() {
    case "$1" in
        "modify")
            if [ -f "/etc/hotplug2.rules" ]; then
                grep -q "$SCRIPT_PATH" /etc/hotplug2.rules && return # already modified

                [ ! -f "/etc/hotplug2.rules.bak" ] && mv /etc/hotplug2.rules /etc/hotplug2.rules.bak
                
                cat /etc/hotplug2.rules.bak > /etc/hotplug2.rules

                cat <<EOT >> /etc/hotplug2.rules
SUBSYSTEM == block, DEVICENAME is set, ACTION ~~ ^(add|remove)$ {
    exec /jffs/scripts/hotplug-event.sh run %SUBSYSTEM% %ACTION% ;
}
SUBSYSTEM == net, DEVICENAME is set, ACTION ~~ ^(add|remove)$ {
    exec /jffs/scripts/hotplug-event.sh run %SUBSYSTEM% %ACTION% ;
}
SUBSYSTEM == misc, DEVICENAME ~~ ^(tun|tap)$, ACTION ~~ ^(add|remove)$ {
    exec /jffs/scripts/hotplug-event.sh run %SUBSYSTEM% %ACTION% ;
}
EOT

                killall hotplug2

                logger -s -t "$SCRIPT_TAG" "Modified hotplug configuration"
            fi
        ;;
        "restore")
            if [ -f "/etc/hotplug2.rules" ] && [ -f "/etc/hotplug2.rules.bak" ]; then
                rm /etc/hotplug2.rules
                cp /etc/hotplug2.rules.bak /etc/hotplug2.rules
                killall hotplug2

                logger -s -t "$SCRIPT_TAG" "Restored original hotplug configuration"
            fi
        ;;
    esac
}

case "$1" in
    "run")
        if [ -n "$2" ] && [ -n "$3" ]; then # handles calls from hotplug
            ARG_SUBSYSTEM="$2"
            ARG_ACTION="$3"

            case "$2" in
                "block"|"net"|"misc")
                    logger -s -t "$SCRIPT_TAG" "Running script (args: \"${ARG_SUBSYSTEM}\" \"${ARG_ACTION}\")"
                ;;
            esac
            
            sh "$SCRIPT_PATH" event "$ARG_SUBSYSTEM" "$ARG_ACTION" &
            [ -n "$EXECUTE_COMMAND" ] && $EXECUTE_COMMAND "$ARG_SUBSYSTEM" "$ARG_ACTION"
        else # handles cron
            if ! grep -q "$SCRIPT_PATH" /etc/hotplug2.rules; then
                hotplug_config modify
            fi
        fi
    ;;
    "event")
        # $2 = subsystem, $3 = action
        case "$2" in
            "block")
                [ -x "/jffs/scripts/usb-mount.sh" ] && /jffs/scripts/usb-mount.sh hotplug
                [ -x "/jffs/scripts/entware.sh" ] && /jffs/scripts/entware.sh hotplug
            ;;
            "net")
                [ -x "/jffs/scripts/usb-network.sh" ] && /jffs/scripts/usb-network.sh hotplug
            ;;
            "misc")
                # empty for now
            ;;
        esac
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        hotplug_config modify
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        hotplug_config restore
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart"
        exit 1
    ;;
esac
