#!/bin/bash

# This script monitors docker containers and create symbolic links to log
# files of all running containers. This will help Fluentd to monitor all
# container logs from single directory.

. /opt/zebrium/etc/functions

CONTAINER_LOG_DIR="/var/lib/zebrium/container_logs"

update_log_links() {
    if ! which docker > /dev/null; then
        return
    fi
    local CONTAINER_IDS=`docker ps --no-trunc --format "{{.ID}}"`

    mkdir -p $CONTAINER_LOG_DIR
    cd $CONTAINER_LOG_DIR

    for C in $CONTAINER_IDS; do
        local LPATH=`docker inspect --format '{{.LogPath}}' $C`
        local LINK=`basename $LPATH`
        if [ ! -f $LINK ]; then
            ln -s $LPATH .
        fi
    done

    for F in `ls`; do
        if [ ! -f $F ]; then
            log INFO "Deleting invalid log file link $F"
            rm -f $F
        fi
    done
}

main() {
    log_start ""
    while : ; do
        update_log_links
        sleep 30
    done
}

main "$@"
