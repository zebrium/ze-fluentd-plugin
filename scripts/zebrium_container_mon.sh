#!/bin/bash
# (C) Sciencelogic, Inc. 2023
# This script monitors docker containers and create symbolic links to log
# files of all running containers. This will help Fluentd to monitor all
# container logs from single directory.

CONTAINER_LOG_DIR="/var/log/zebrium/container_logs"

date_formatted() {
    # ISO-8601 timestamp, with milliseconds
    /bin/date '+%Y-%m-%dT%H:%M:%S.%03N%:z'
}

# Usage: log {DEBUG|INFO|WARNING|ERROR|CRITICAL} msg
log() {
    local ts=$(date_formatted)
    local severity=$1
    shift

    printf "%s %5s %-6s %s\n" "${ts}" "$$" "${severity}:" "$@"
    #echo "${ts} $$ ${severity}: $@"
    if [ -n "${LOGFILE}" ]; then
        echo "${ts} $$ ${severity}: $@" >> $LOGFILE
    fi
}

log_start() {
    log INFO "----------------------------------------------"
    log INFO "Starting $0: $@"
}

update_log_links() {
    if ! which docker > /dev/null; then
        return
    fi
    local CONTAINER_IDS=`docker ps --no-trunc --format "{{.ID}}"`

    mkdir -p $CONTAINER_LOG_DIR
    cd $CONTAINER_LOG_DIR

    for C in $CONTAINER_IDS; do
        local LPATH=`docker inspect --format '{{.LogPath}}' $C`
        if [ -z "$LPATH" ]; then
            log INFO "log path is empty, container $C may have been deleted"
            continue
        fi
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
