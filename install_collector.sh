#!/bin/bash
# (C) Zebrium, Inc. 2019
# All rights reserved
# Licensed under Simplified BSD License (see LICENSE)
# Zebrium Log Collector installation script: install and set up the log collector.

set -e
LOG_FILE="/tmp/zlog-collector-install.log.$$"

PROG=${0##*/}

function log() {
    local LOG_LEVEL=`echo $1 | tr '[:upper:]' '[:lower:]'`
    shift
    local MSG="$*"
    if [ "$LOG_LEVEL" = "error" ]; then
        echo -e "\033[31m$MSG\033[0m"
    else
        echo -e "\033[34m$MSG\n\033[0m"
    fi
}

function usage() {
    echo "$PROG [-o <install | uninstall | upgrade> ]" 1>&2
    exit 1
}

function err_exit() {
    echo -e "\033[31m$*\033[0m" 1>&2
    exit 1
}

function cleanup() {
    rm -f $NPIPE
    rm -rf $TEMP_DIR
}

function on_error() {
    printf "\033[31m$ERROR_MESSAGE
It looks like you hit an issue when trying to install zebrium log collector.

Please send an email to support@zebrium.com with the contents of $LOG_FILE
and we'll do our very best to help you solve your problem.\n\033[0m\n"
    cleanup
}

function update_td_agent_service_file() {
    if ! grep -q 'ExecStartPre=' /lib/systemd/system/td-agent.service; then
        log info "Add ExecStartPre script for td-agent service"
        $SUDO_CMD sed -i '/^ExecStart=.*/i ExecStartPre=/opt/zebrium/bin/update_fluentd_cfg.rb' /lib/systemd/system/td-agent.service
    fi
}

function create_config() {
    local MAIN_CONF_FILE=$TEMP_DIR/td-agent.conf
    local USER_CONF_FILE=$TEMP_DIR/user.conf
    local SYSTEMD_CONF_FILE=$TEMP_DIR/systemd.conf
    local CONTAINERS_CONF_FILE=$TEMP_DIR/containers.conf

    local SYSTEMD_INCLUDE=""
    if which systemctl > /dev/null 2>&1; then
        log info "Systemd detected, creating systemd config"
        SYSTEMD_INCLUDE="@include conf.d/systemd.conf"
    fi
    cat << EOF > $SYSTEMD_CONF_FILE
<source>
  @type systemd
  path "$JOURNAL_DIR"
  <storage>
    @type local
    path "/var/log/td-agent/fluentd-journald-cursor.json"
  </storage>
  tag journal
  read_from_head true
</source>

<match journal>
  @type rewrite_tag_filter
  <rule>
    key _SYSTEMD_UNIT
    pattern /^(.+)\.service$/
    tag systemd.service.\$1
  </rule>
</match>

<match systemd.service.docker>
  @type rewrite_tag_filter
  <rule>
    key CONTAINER_ID_FULL
    pattern /.+/
    tag containers.\$1
  </rule>
</match>
EOF

    DEFAULT_LOG_PATHS="/var/log/*.log,/var/log/messages,/var/log/syslog,/var/log/secure"
    ZE_LOG_PATHS="${ZE_LOG_PATHS:-$DEFAULT_LOG_PATHS}"
    cat << EOF > $MAIN_CONF_FILE
<source>
  @type tail
  path "$ZE_LOG_PATHS"
  format none
  path_key tailed_path
  pos_file /var/log/td-agent/sys_logs.pos
  tag node.logs.*
  read_from_head true
</source>

@include conf.d/user.conf
@include conf.d/containers.conf
$SYSTEMD_INCLUDE

<match **>
  @type zebrium
  ze_log_collector_url "$ZE_LOG_COLLECTOR_URL"
  ze_log_collector_token "$ZE_LOG_COLLECTOR_TOKEN"
  ze_host_tags "$ZE_HOST_TAGS"
  @log_level "info"
  <buffer tag>
    @type file
    path /var/log/td-agent/buffer/out_zebrium.*.buffer
    flush_mode "interval"
    flush_interval "60s"
  </buffer>
</match>
EOF
    # "path" can not be empty in Fluentd config, so we add a dummy file
    # if user does not provide log file path
    ZE_USER_LOG_PATHS="${ZE_USER_LOG_PATHS:-/tmp/__dummy__.log}"
    cat << EOF > $USER_CONF_FILE
<source>
  @type tail
  path "$ZE_USER_LOG_PATHS"
  path_key tailed_path
  pos_file /var/log/td-agent/user_logs.pos
  <parse>
    @type none
  </parse>
  tag node.logs.*
</source>
EOF

    cat << EOF > $CONTAINERS_CONF_FILE
<source>
  @type tail
  path "/var/lib/zebrium/container_logs/*.log"
  path_key tailed_path
  pos_file /var/log/td-agent/containers_logs.pos
  read_from_head true
  tag containers.*
  format json
  time_format %Y-%m-%dT%H:%M:%S.%NZ
  utc true
</source>
EOF

    $SUDO_CMD mkdir -p /etc/td-agent
    $SUDO_CMD cp -f $MAIN_CONF_FILE /etc/td-agent/td-agent.conf
    $SUDO_CMD mkdir -p /etc/td-agent/conf.d
    $SUDO_CMD cp -f $USER_CONF_FILE /etc/td-agent/conf.d
    $SUDO_CMD cp -f $CONTAINERS_CONF_FILE /etc/td-agent/conf.d
    if [ -n "$SYSTEMD_INCLUDE" ]; then
        $SUDO_CMD cp -f $SYSTEMD_CONF_FILE /etc/td-agent/conf.d
    fi
}

function is_log_collector_installed() {
    egrep -q '@type[[:space:]]+zebrium' /etc/td-agent/td-agent.conf 2>/dev/null
}

function has_systemd() {
    which systemctl > /dev/null 2>&1
}

function is_td_agent_service_installed() {
    has_systemd && systemctl -a | grep -q td-agent
}

function do_uninstall() {
    log info "Stopping Zebrium log collector services"
    if has_systemd; then
        $SUDO_CMD systemctl stop zebrium-container-mon
        $SUDO_CMD systemctl disable zebrium-container-mon
        $SUDO_CMD systemctl stop td-agent
    else
        $SUDO_CMD /etc/init.d/td-agent stop
    fi
    log info "Removing packages"
    if [ "$OS" = "RedHat" -o "$OS" = "Amazmon" ]; then
        $SUDO_CMD yum remove -y td-agent
    elif [ "$OS" = "Debian" ]; then
        $SUDO_CMD apt-get -y remove td-agent
    fi
    $SUDO_CMD rm -rf /etc/zebrium /opt/zebrium
    $SUDO_CMD rm -rf /etc/zebrium /opt/zebrium /etc/td-agent
    log info "Removed Zebrium log collector"
}

function main() {
    TEMP_DIR=/tmp/zlog-collector-install.$$
    mkdir -p $TEMP_DIR

    # Set up a named pipe for logging
    NPIPE=/tmp/$$.tmp
    mknod $NPIPE p

    # Log all output to a log for error checking
    tee <$NPIPE $LOG_FILE &
    exec 1>&-
    exec 1>$NPIPE 2>&1
    trap cleanup EXIT
    trap on_error ERR

    local OP="install"
    local OP_OPT=""
    while getopts "o:" OPT; do
        case $OPT in
            o)
                OP_OPT=$OPTARG
                ;;
            *)
                usage
        esac
    done

    OP_OPT=`echo $OP_OPT | tr '[:upper:]' '[:lower:]'`
    if [ -z "$OP_OPT" ]; then
        OP_OPT="$ZE_OP"
    fi
    if [ -n "$OP_OPT" ]; then
        if [ "$OP_OPT" != "install" -a "$OP_OPT" != "uninstall" -a "$OP_OPT" != "upgrade" ]; then
            usage
        fi
        OP="$OP_OPT"
    elif is_log_collector_installed; then
        OP="upgrade"
    fi

    if [ $(command -v curl) ]; then
        DL_CMD="curl --connect-timeout 30 --retry 3 --retry-delay 5 -O -L -f"
        DL_SH_CMD="curl --connect-timeout 30 --retry 3 --retry-delay 5 -q -L"
    else
        DL_CMD="wget --quiet --dns-timeout=30 --connect-timeout=30"
        DL_SH_CMD="wget --dns-timeout=30 --connect-timeout=30 -qO-"
    fi

    OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-0}
    START_SERVICES=${START_SERVICES:-1}

    # OS/Distro Detection
    # Try lsb_release, fallback with /etc/issue then uname command
    KNOWN_DISTRIBUTION="(Debian|Ubuntu|RedHat|REDHAT|CentOS|Amazon)"
    DISTRIBUTION=$(lsb_release -d 2>/dev/null | grep -Eo $KNOWN_DISTRIBUTION  || grep -Eo $KNOWN_DISTRIBUTION /etc/issue 2>/dev/null || grep -Eo $KNOWN_DISTRIBUTION /etc/Eos-release 2>/dev/null || grep -m1 -Eo $KNOWN_DISTRIBUTION /etc/os-release 2>/dev/null || uname -s)
    if [ $DISTRIBUTION = "REDHAT" ]; then
        # RHEL8 has "REDHAT" string instead of RedHat
        DISTRIBUTION=RedHat
    fi
    # Better detection for RHEL8
    if grep -q 'Red Hat Enterprise Linux' /etc/os-release; then
        DISTRIBUTION=RedHat
    fi

    if [ $DISTRIBUTION = "Darwin" ]; then
        err_exit "Mac is not supported."
    elif [ -f /etc/debian_version -o "$DISTRIBUTION" == "Debian" -o "$DISTRIBUTION" == "Ubuntu" -o "$DISTRIBUTION" == "Linux" ]; then
        OS="Debian"
    elif [ -f /etc/redhat-release -o "$DISTRIBUTION" == "RedHat" -o "$DISTRIBUTION" == "CentOS" ]; then
        OS="RedHat"
    elif [ "$DISTRIBUTION" == "Amazon" ]; then
        OS="Amazon"
    fi

    # Root user detection
    if [ $(echo "$UID") = "0" ]; then
        SUDO_CMD=''
    else
        SUDO_CMD='sudo'
        if ! which $SUDO_CMD > /dev/null 2>&1; then
            err_exit "sudo command not found. Are you trying to install inside container?"
        fi
    fi

    if [ "$OP" = "upgrade" ]; then
        if ! is_log_collector_installed; then
            err_exit "Log collector is not installed, can not upgrade"
        fi
    fi
    if [ "$OP" = "install" -o $OVERWRITE_CONFIG -ne 0 ]; then
        if [ -z "$ZE_LOG_COLLECTOR_URL" ]; then
            err_exit "ZE_LOG_COLLECTOR_URL environment variable is not set"
        fi
        if [ -z "$ZE_LOG_COLLECTOR_TOKEN" ]; then
            err_exit "ZE_LOG_COLLECTOR_TOKEN environment variable is not set"
        fi
    elif [ "$OP" = "uninstall" ]; then
        do_uninstall
        exit 0
    fi

    # Install the Fluentd, plugin and their depedencies
    if [ $OS = "RedHat" ]; then
        DEFAULTS_DIR=/etc/sysconfig
        TD_AGENT_INSTALLED=$(yum list installed td-agent > /dev/null 2>&1 || echo "no")
        if [ "$TD_AGENT_INSTALLED" == "no" ]; then
            log info "Installing log collector dependencies"
            $SUDO_CMD yum -y install gcc make ruby-devel rubygems
            $DL_SH_CMD https://toolbelt.treasuredata.com/sh/install-redhat-td-agent3.sh | sh
        fi
    elif [ $OS = "Amazon" ]; then
        DEFAULTS_DIR=/etc/sysconfig
        TD_AGENT_INSTALLED=$(yum list installed td-agent > /dev/null 2>&1 || echo "no")
        AMZN_VERS=`uname -r | egrep -o  'amzn[[:digit:]]+' | sed 's/amzn//'`
        if [ "$TD_AGENT_INSTALLED" == "no" ]; then
            log info "Installing log collector dependencies"
            $SUDO_CMD yum -y install gcc ruby-devel rubygems
            $DL_SH_CMD https://toolbelt.treasuredata.com/sh/install-amazon${AMZN_VERS}-td-agent3.sh | sh
        fi
    elif [ $OS = "Debian" ]; then
        DEFAULTS_DIR=/etc/default
        IS_UBUNTU=`uname -a  | grep -i Ubuntu | wc -l`
        if which lsb_release > /dev/null 2>&1; then
            CODE_NAME=`lsb_release -c | awk '{ print $2 }'`
        else
            RELEASE_VERS=`head -1 /etc/issue | awk '{ print $3 }'`
            if [ "$RELEASE_VERS" == "8" ]; then
                CODE_NAME="jessie"
            fi
        fi
        if [ "$CODE_NAME" == "focal" ]; then
            log info "Ubuntu 20.04 (focal) detected, use compatible software from bionic."
            CODE_NAME=bionic
        fi
        if [ "$CODE_NAME" == "tricia" -o "$CODE_NAME" == "tina" -o "$CODE_NAME" == "tessa" -o "$CODE_NAME" == "tara" ]; then
            CODE_NAME="bionic"
        fi
        if [ "$CODE_NAME" == "sylvia" -o "$CODE_NAME" == "sonya" -o "$CODE_NAME" == "serena" -o "$CODE_NAME" == "sarah" ]; then
            CODE_NAME="xenial"
        fi
        FLAVOR_STR=""
        if [ $IS_UBUNTU -ge 1 ]; then
            FLAVOR_STR="ubuntu"
        else
            FLAVOR_STR="debian"
        fi

        log info "Installing package dependies"
        $SUDO_CMD apt-get update || log info "'apt-get update' failed."
        $SUDO_CMD apt-get install -y build-essential ruby-dev

        log info "Installing log collector dependencies"
        $DL_SH_CMD https://toolbelt.treasuredata.com/sh/install-${FLAVOR_STR}-${CODE_NAME}-td-agent3.sh | sh
    else
        log info "Your OS or distribution are not supported by this install script."
        exit;
    fi

    log info "Installing fluent-plugin-systemd"
    $SUDO_CMD td-agent-gem install fluent-plugin-systemd
    log info "Installing docker-api"
    $SUDO_CMD td-agent-gem install docker-api
    log info "Uninstalling fluent-plugin-zebrium_output"
    $SUDO_CMD td-agent-gem uninstall fluent-plugin-zebrium_output

    cd $TEMP_DIR
    log info "Downloading fluent-plugin-zebrium_output"
    $DL_CMD https://github.com/zebrium/ze-fluentd-plugin/raw/master/pkgs/fluent-plugin-zebrium_output-1.37.0.gem
    log info "Installing fluent-plugin-zebrium_output"
    $SUDO_CMD td-agent-gem install fluent-plugin-systemd fluent-plugin-zebrium_output

    log info "Downloading zebrium-fluentd package"
    $DL_CMD https://github.com/zebrium/ze-fluentd-plugin/raw/master/pkgs/zebrium-fluentd-1.18.0.tgz
    log info "Installing zebrium-fluentd"
    $SUDO_CMD tar -C /opt -xf zebrium-fluentd-1.18.0.tgz

    TD_DEFAULT_FILE=$DEFAULTS_DIR/td-agent
    if [ ! -e $TD_DEFAULT_FILE ]; then
        $SUDO_CMD sh -c "echo TD_AGENT_USER=root >> $TD_DEFAULT_FILE"
        $SUDO_CMD sh -c "echo TD_AGENT_GROUP=root >> $TD_DEFAULT_FILE"
    fi
    if [ -f /var/log/td-agent/td-agent.log ]; then
        $SUDO_CMD chown root:root /var/log/td-agent/td-agent.log
    fi

    if has_systemd; then
        $SUDO_CMD mkdir -p /etc/systemd/system/td-agent.service.d
        $SUDO_CMD sh -c '/bin/echo -e "[Service]\nUser=root\nGroup=root\n" > /etc/systemd/system/td-agent.service.d/override.conf'
        update_td_agent_service_file

        $SUDO_CMD cp -f /opt/zebrium/etc/zebrium-container-mon.service /etc/systemd/system/
        pushd /etc/systemd/system/ > /dev/null
        $SUDO_CMD systemctl enable zebrium-container-mon.service
        popd > /dev/null
        $SUDO_CMD systemctl daemon-reload
    fi

    # Set the configuration
    if egrep -q '@type[[:space:]]+zebrium' /etc/td-agent/td-agent.conf 2>/dev/null && [ $OVERWRITE_CONFIG -eq 0 ]; then
        log info "Keeping old /etc/td-agent/td-agent.conf configuration file"
    else
        if [ -e /etc/td-agent/td-agent.conf ]; then
            log info "Saving current /etc/td-agent/td-agent.conf to /etc/td-agent/td-agent.backup"
            $SUDO_CMD mv -f /etc/td-agent/td-agent.conf /etc/td-agent/td-agent.backup
        fi
        log info "Creating new fluentd config and adding API server URL and API key"
        if [ -e /var/log/journal ]; then
            JOURNAL_DIR="/var/log/journal"
        elif [ -e /run/log/journal ]; then
            JOURNAL_DIR="/run/log/journal"
        else
            JOURNAL_DIR="/var/log/journal"
        fi
        create_config
    fi

    restart_cmd="$SUDO_CMD /etc/init.d/td-agent restart"
    if has_systemd; then
        restart_cmd="$SUDO_CMD systemctl restart td-agent"
        if ! is_td_agent_service_installed; then
            $SUDO_CMD systemctl enable td-agent
        fi
    fi

    if [ $START_SERVICES -eq 0 ]; then
        if is_td_agent_service_installed; then
            printf "\033[32m

Zebrium Log Collector is not started.

To start Log Collector manually, run:
    sudo systemctl start zebrium-container-mon
    sudo systemctl start td-agent

\033[0m"

        else
            printf "\033[32m

Zebrium Log Collector is not started.

To start Log Collector manually, run:
    sudo /etc/init.d/td-agent start

\033[0m"
        fi
        exit 0
    else
        if has_systemd && systemctl -a | grep -q zebrium-container-mon; then
            $SUDO_CMD systemctl start zebrium-container-mon.service
        fi
    fi

    log info "Starting Zebrium log collector..."
    # We have seen systemd returns error on first start of td-agent, so we ignore error and just check
    # status
    set +e
    trap - ERR

    eval $restart_cmd >> $LOG_FILE 2>&1

    if is_td_agent_service_installed; then
        while : ; do
            log info "Waiting for log collector to come up ..."
            systemctl status td-agent > /dev/null && break
            sleep 5
        done
        printf "\033[32m

Zebrium Log Collector is running.

If you ever want to stop the Log Collector, run:

    sudo systemctl stop zebrium-container-mon
    sudo systemctl stop td-agent

And to run it again run:

    sudo systemctl start zebrium-container-mon
    sudo systemctl start td-agent

\033[0m"

    else
        while : ; do
            log info "Waiting for log collector to come up ..."
            $SUDO_CMD /etc/init.d/td-agent status && break
            sleep 5
        done
        printf "\033[32m

Zebrium Log Collector is running.

If you ever want to stop the Log Collector, run:

    sudo /etc/init.d/td-agent stop

And to run it again run:

    sudo /etc/init.d/td-agent start

\033[0m"
    fi
}

main "$@"
