#!/bin/sh
# Made by Jack'lul <jacklul.github.io>
#
# Setup and enable swap file on startup
#
# Based on:
#  https://github.com/decoderman/amtm/blob/master/amtm_modules/swap.mod
#

#shellcheck disable=SC2155

readonly SCRIPT_PATH="$(readlink -f "$0")"
readonly SCRIPT_NAME="$(basename "$SCRIPT_PATH" .sh)"
readonly SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
readonly SCRIPT_CONFIG="$SCRIPT_DIR/$SCRIPT_NAME.conf"
readonly SCRIPT_TAG="$(basename "$SCRIPT_PATH")"

SWAP_FILE="" # swap file path, like "/tmp/mnt/USBDEVICE/swap.img", leave empty to search for it in /tmp/mnt/*/swap.img
SWAP_SIZE=128000 # swap file size, changing after swap is created requires it to be manually removed, 128000 = 128MB

if [ -f "$SCRIPT_CONFIG" ]; then
    #shellcheck disable=SC1090
    . "$SCRIPT_CONFIG"
fi

if [ -z "$SWAP_FILE" ]; then
    for DIR in /tmp/mnt/*; do
        if [ -d "$DIR" ] && [ -f "$DIR/swap.img" ]; then
            SWAP_FILE="$DIR/swap.img"
            break
        fi
    done
fi

case "$1" in
    "run")
        if [ "$(nvram get usb_idle_enable)" != "0" ]; then
            logger -s -t "$SCRIPT_TAG" "Unable to enable swap - USB Idle timeout is set"
            
            cru d "$SCRIPT_NAME"
        else
            if ! grep -q "file" /proc/swaps; then
                if [ -d "$(dirname "$SWAP_FILE")" ] && [ ! -f "$SWAP_FILE" ]; then
                    sh "$SCRIPT_PATH" create
                fi

                if [ -f "$SWAP_FILE" ]; then
                    if swapon "$SWAP_FILE" ; then
                        #shellcheck disable=SC2012
                        logger -s -t "$SCRIPT_TAG" "Enabled swap on $SWAP_FILE ($(ls -hs "$SWAP_FILE" | awk '{print $1}'))"
                    else
                        logger -s -t "$SCRIPT_TAG" "Failed to enable swap on $SWAP_FILE"
                    fi
                fi
            fi
        fi
    ;;
    "create")
        [ -n "$2" ] && SWAP_FILE="$2"
        [ -n "$3" ] && SWAP_SIZE="$3"
        
        [ -z "$SWAP_FILE" ] && { logger -s -t "$SCRIPT_TAG" "Swap file is not set"; exit 1; }
        [ -z "$SWAP_SIZE" ] && { logger -s -t "$SCRIPT_TAG" "Swap size is not set"; exit 1; }

        set -e

        echo "Creating swap file..."
        touch "$SWAP_FILE"
        dd if=/dev/zero of="$SWAP_FILE" bs=1k count="$SWAP_SIZE"
        mkswap "$SWAP_FILE"

        set +e
    ;;
    "start")
        cru a "$SCRIPT_NAME" "*/1 * * * * $SCRIPT_PATH run"

        sh "$SCRIPT_PATH" run
    ;;
    "stop")
        cru d "$SCRIPT_NAME"

        if [ -n "$SWAP_FILE" ]; then
            sync
            echo 3 > /proc/sys/vm/drop_caches

            if swapoff "$SWAP_FILE" ; then
                logger -s -t "$SCRIPT_TAG" "Disabled swap on $SWAP_FILE"
            else
                logger -s -t "$SCRIPT_TAG" "Failed to disable swap on $SWAP_FILE"
            fi
        fi
    ;;
    "restart")
        sh "$SCRIPT_PATH" stop
        sh "$SCRIPT_PATH" start
    ;;
    *)
        echo "Usage: $0 run|start|stop|restart|create"
        exit 1
    ;;
esac
