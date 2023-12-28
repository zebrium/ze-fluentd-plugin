#!/bin/bash
# (C) Sciencelogic, Inc. 2023
# All rights reserved
# Licensed under Simplified BSD License (see LICENSE)
# Zebrium Log Collector installation script: install and set up the log collector.

set -e
LOG_FILE="/tmp/zlog-collector-install.log.$$"
VERSION=1.51.0

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
    print_debug_info
    printf "\033[31m$ERROR_MESSAGE
It looks like you hit an issue when trying to install the zebrium log collector.

Please send an email to support@zebrium.com with the contents of $LOG_FILE
and we'll do our very best to help you solve your problem.\n\033[0m\n"
    cleanup
}

function update_td_agent_service_file() {
    if ! grep -q 'ExecStartPre=' /lib/systemd/system/fluentd.service; then
        log info "Add ExecStartPre script for fluentd service"
        $SUDO_CMD sed -i '/^ExecStart=.*/i ExecStartPre=/opt/fluent/bin/ruby /opt/zebrium/bin/update_fluentd_cfg.rb' /lib/systemd/system/fluentd.service
    fi
    if grep -q 'Environment=LD_PRELOAD=/opt/fluent/lib/libjemalloc.so' /lib/systemd/system/fluentd.service; then
        log info "Disabling Malloc as a temp solution to memory leak crash"
        $SUDO_CMD sed -i 's/^Environment=LD_PRELOAD=\/opt\/fluent\/lib\/libjemalloc.so/#Environment=LD_PRELOAD=\/opt\/fluent\/lib\/libjemalloc.so/' /lib/systemd/system/fluentd.service
    fi
}

function create_config() {
    local MAIN_CONF_FILE=$TEMP_DIR/fluentd.conf
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
    path "/var/log/fluent/fluentd-journald-cursor.json"
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
  pos_file /var/log/fluent/sys_logs.pos
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
  ze_log_collector_type "linux"
  ze_host_tags "$ZE_HOST_TAGS"
  <buffer tag>
    @type file
    path /var/log/fluent/buffer/out_zebrium.*.buffer
    chunk_limit_size "1MB"
    chunk_limit_records "4096"
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
  pos_file /var/log/fluent/user_logs.pos
  <parse>
    @type none
  </parse>
  tag node.logs.*
</source>
EOF

    cat << EOF > $CONTAINERS_CONF_FILE
<source>
  @type tail
  path "/var/log/zebrium/container_logs/*.log"
  path_key tailed_path
  pos_file /var/log/fluent/containers_logs.pos
  read_from_head true
  tag containers.*
  format json
  time_format %Y-%m-%dT%H:%M:%S.%NZ
  utc true
</source>
EOF

    $SUDO_CMD mkdir -p /etc/fluent
    $SUDO_CMD cp -f $MAIN_CONF_FILE /etc/fluent/fluentd.conf
    $SUDO_CMD mkdir -p /etc/fluent/conf.d
    $SUDO_CMD cp -f $USER_CONF_FILE /etc/fluent/conf.d
    $SUDO_CMD cp -f $CONTAINERS_CONF_FILE /etc/fluentconf.d
    if [ -n "$SYSTEMD_INCLUDE" ]; then
        $SUDO_CMD cp -f $SYSTEMD_CONF_FILE /etc/fluent/conf.d
    fi
}

function is_log_collector_installed() {
    egrep -q '@type[[:space:]]+zebrium' /etc/fluent/fluentd.conf 2>/dev/null
}

function has_systemd() {
    which systemctl > /dev/null 2>&1
}

function is_td_agent_service_installed() {
    has_systemd && systemctl -a | grep -q fluentd
}

function do_uninstall() {
    log info "Stopping Zebrium log collector services"
    if has_systemd; then
        $SUDO_CMD systemctl stop zebrium-container-mon
        $SUDO_CMD systemctl disable zebrium-container-mon
        $SUDO_CMD systemctl stop fluentd
    else
        $SUDO_CMD /etc/init.d/fluentd stop
    fi
    log info "Removing packages"
    if [ "$OS" = "RedHat" -o "$OS" = "Amazon" ]; then
        $SUDO_CMD yum remove -y fluentd
    elif [ "$OS" = "Debian" ]; then
        $SUDO_CMD apt-get -y remove fluentd
    fi
    $SUDO_CMD rm -rf /etc/zebrium /opt/zebrium
    $SUDO_CMD rm -rf /etc/zebrium /opt/zebrium /etc/fluentd
    log info "Removed Zebrium log collector"
}

function download_installer() {
    local INSTALLER_URL=$1
    $DL_CMD $INSTALLER_URL
    local SH_FILE=`basename $INSTALLER_URL`
    sed -i -e 's/sudo[[:space:]]\+-k//' -e 's/sudo[[:space:]]\+sh/sh/' $SH_FILE
}

function download_and_run_installer() {
    local INSTALLER_URL=$1
    if [ "$SUDO_DISABLED" = "1" ]; then
        $DL_CMD $INSTALLER_URL
        local SH_FILE=`basename $INSTALLER_URL`
        log info "Patching $SH_FILE"
        sed -i -e 's/sudo[[:space:]]\+-k//' -e 's/sudo[[:space:]]\+sh/sh/' $SH_FILE
        sh $SH_FILE
    else
        $DL_SH_CMD $INSTALLER_URL | sh
    fi
}

function print_debug_info() {
    echo "Installer version $VERSION"
    echo ""
    echo "OS information:"
    echo "uname -a"
    uname -a
    echo ""
    if [ -f /etc/os-release ]; then
        echo "cat /etc/os-release"
        cat /etc/os-release
        echo ""
    else
        echo "/etc/os-release does not exist"
        echo ""
    fi
    if [ -f /etc/issue ]; then
        echo "cat /etc/issue"
        cat /etc/issue
    else
        echo "/etc/issue does not exist"
    fi
    if which lsb_release > /dev/null 2>&1; then
        echo "lsb_release -c"
        lsb_release -c | awk '{ print $2 }'
    else 
        echo "lsb_release command not found"
    fi
}

function main() {
    TEMP_DIR=/tmp/zlog-collector-install.$$
    mkdir -p $TEMP_DIR
    cd $TEMP_DIR

    # Set up a named pipe for logging
    NPIPE=/tmp/$$.tmp
    mknod $NPIPE p

    # Log all output to a log for error checking
    tee <$NPIPE $LOG_FILE &
    exec 1>&-
    exec 1>$NPIPE 2>&1
    trap cleanup EXIT
    trap on_error ERR

    print_debug_info

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

    # Determine which download command to use for retrieval
    if [ $(command -v curl) ]; then
        DL_CMD="curl --connect-timeout 30 --retry 3 --retry-delay 5 -O -L -f"
        DL_SH_CMD="curl --connect-timeout 30 --retry 3 --retry-delay 5 -q -L"
    elif [ $(wget -v curl) ]; then
        DL_CMD="wget --quiet --dns-timeout=30 --connect-timeout=30"
        DL_SH_CMD="wget --dns-timeout=30 --connect-timeout=30 -qO-"
    else 
        err_exit "Neither curl nor wget found. Please install one of them and try again."
    fi

    OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-0}
    START_SERVICES=${START_SERVICES:-1}

    # OS/Distro Detection
    # Try lsb_release, fallback with /etc/issue then uname command
    KNOWN_DISTRIBUTION="(Debian|Ubuntu|Red Hat|RedHat|REDHAT|CentOS|Amazon|Oracle Linux)"
    DISTRIBUTION=$(lsb_release -d 2>/dev/null | grep -Eo "$KNOWN_DISTRIBUTION"  || grep -Eo "$KNOWN_DISTRIBUTION" /etc/issue 2>/dev/null || grep -Eo "$KNOWN_DISTRIBUTION" /etc/Eos-release 2>/dev/null || grep -m1 -Eo "$KNOWN_DISTRIBUTION" /etc/os-release 2>/dev/null || uname -s)
    if [ "$DISTRIBUTION" = "REDHAT" -o "$DISTRIBUTION" = "Red Hat" ]; then
        DISTRIBUTION=RedHat
    fi
    if [ "$DISTRIBUTION" = "Oracle Linux" ]; then
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
    if [ $(echo "$UID") = "0" -o "$SUDO_DISABLED" = "1" ]; then
        log info "SUDO_DISABLED is set to 1, must be running as the root user"
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

    # ---------------------
    # RedHat Install Section
    # ---------------------
    if [ $OS = "RedHat" ]; then
        DEFAULTS_DIR=/etc/sysconfig
        MAJOR_VERS=""
        if which lsb_release > /dev/null 2>&1; then
            MAJOR_VERS=`lsb_release -r | awk '{ print $2 }' | cut -f1 -d.`
        else
            MAJOR_VERS=`awk -F= '/VERSION_ID/ { print $2 }' /etc/os-release | sed 's/"//g' | cut -f1 -d.`
        fi
        if (($MAJOR_VERS < 7)); then
            err_exit "RHEL/CentOS $MAJOR_VERS is not supported"
        fi
        # Assume Fedora, attempt to map known versions
        if (($MAJOR_VERS >28)); then
            MAJOR_VERS=8
        elif (($MAJOR_VERS >20)); then
            MAJOR_VERS=7
        fi
        TD_AGENT_INSTALLED=$(yum list installed fluentd > /dev/null 2>&1 || echo "no")
        if [ "$TD_AGENT_INSTALLED" == "no" ]; then
            # treasuredata releases are '7', '8' etc but releasever added by installed may not match
            SH_FILE=install-redhat-fluent-package5.sh
            download_installer https://toolbelt.treasuredata.com/sh/$SH_FILE
            MAJOR_VERS=`echo $MAJOR_VERS | sed 's/\..*//'`
            sed -i -e "s/\\\\\$releasever/$MAJOR_VERS/" $SH_FILE
            if [ "$SUDO_DISABLED" = "1" ]; then
                bash $SH_FILE && rm $SH_FILE
            else 
                $SUDO_CMD bash $SH_FILE && rm $SH_FILE
            fi
        fi
    # ---------------------
    # Amazon Linux Install Section
    # ---------------------
    elif [ $OS = "Amazon" ]; then
        DEFAULTS_DIR=/etc/sysconfig
        TD_AGENT_INSTALLED=$(yum list installed fluentd > /dev/null 2>&1 || echo "no")
        # OLD CHECK: AMZN_VERS=`uname -r | egrep -o  'amzn[[:digit:]]+' | sed 's/amzn//'`

        # NEW CHECK: Check if /etc/os-release file exists
        if [ -f /etc/os-release ]; then
            # Use grep to search for specific strings in the os-release file
            if grep -q 'Amazon Linux 2023' /etc/os-release; then
                AMZN_VERS="amazon2023"
            elif grep -q 'Amazon Linux 2' /etc/os-release; then
                AMZN_VERS="amazon2"
            else
                log error "Unknown Amazon Linux version"
            fi
        else
            log error "The /etc/os-release file does not exist. It should if this is an Amazon Linux box, so not sure how we got here."
        fi

        if [ "$TD_AGENT_INSTALLED" == "no" ]; then
            echo "download_and_run_installer https://toolbelt.treasuredata.com/sh/install-${AMZN_VERS}-fluent-package5.sh"
            download_and_run_installer https://toolbelt.treasuredata.com/sh/install-${AMZN_VERS}-fluent-package5.sh
        fi
    # ---------------------
    # Debian/Ubuntu Install Section
    # ---------------------
    elif [ $OS = "Debian" ]; then
        DEFAULTS_DIR=/etc/default
        IS_UBUNTU=`cat /etc/os-release | grep -i Ubuntu | wc -l`
        CODE_NAME=$(grep VERSION_CODENAME /etc/os-release | cut -d'=' -f2)
        if [ -z "$CODE_NAME" ]; then
            # Fallback for older versions or if VERSION_CODENAME is missing
            err_exit "Your OS or distribution is not supported by this install script."
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
        log info "Flavor of package: ${FLAVOR_STR} and code name: ${CODE_NAME} detected"
        
        log info "Installing log collector from https://toolbelt.treasuredata.com/sh/install-${FLAVOR_STR}-${CODE_NAME}-fluent-package5.sh" 
        download_and_run_installer https://toolbelt.treasuredata.com/sh/install-${FLAVOR_STR}-${CODE_NAME}-fluent-package5.sh
    else
        err_exit info "Your OS or distribution is not supported by this install script."
    fi

    if ! command -v fluentd &> /dev/null; then
        err_exit "Fluentd installation failed"
    fi

    log info "Installing fluent-plugin-systemd"
    $SUDO_CMD fluent-gem install fluent-plugin-systemd
    log info "Installing docker-api"
    $SUDO_CMD fluent-gem install docker-api
    log info "Uninstalling fluent-plugin-zebrium_output"
    $SUDO_CMD fluent-gem uninstall fluent-plugin-zebrium_output

    log info "Installing fluent-plugin-zebrium_output"
    $SUDO_CMD fluent-gem install fluent-plugin-systemd fluent-plugin-zebrium_output

    log info "Downloading zebrium-fluentd package"
    $DL_CMD https://github.com/zebrium/ze-fluentd-plugin/releases/latest/download/zebrium-fluentd.tar.gz
    log info "Installing zebrium-fluentd"
    $SUDO_CMD tar -C /opt -xf zebrium-fluentd.tar.gz
    log info "Cleaning up zebrium-fluentd package"
    $SUDO_CMD rm zebrium-fluentd.tar.gz


    TD_DEFAULT_FILE=$DEFAULTS_DIR/fluent
    if [ ! -e $TD_DEFAULT_FILE ]; then
        $SUDO_CMD sh -c "echo TD_AGENT_USER=root >> $TD_DEFAULT_FILE"
        $SUDO_CMD sh -c "echo TD_AGENT_GROUP=root >> $TD_DEFAULT_FILE"
    fi
    if [ -f /var/log/fluent/fluentd.log ]; then
        $SUDO_CMD chown root:root /var/log/fluent/fluentd.log
    fi

    if has_systemd; then
        $SUDO_CMD mkdir -p /etc/systemd/system/fluentd.service.d
        $SUDO_CMD sh -c '/bin/echo -e "[Service]\nUser=root\nGroup=root\n" > /etc/systemd/system/fluentd.service.d/override.conf'
        update_td_agent_service_file

        $SUDO_CMD cp -f /opt/zebrium/etc/zebrium-container-mon.service /etc/systemd/system/
        pushd /etc/systemd/system/ > /dev/null
        $SUDO_CMD systemctl enable zebrium-container-mon.service
        popd > /dev/null
        $SUDO_CMD systemctl daemon-reload
    fi

    # Set the configuration
    if egrep -q '@type[[:space:]]+zebrium' /etc/fluent/fluentd.conf 2>/dev/null && [ $OVERWRITE_CONFIG -eq 0 ]; then
        log info "Keeping old /etc/fluent/fluentd.conf configuration file"
    else
        if [ -e /etc/fluent/fluentd.conf ]; then
            log info "Saving current /etc/fluent/fluentd.conf to /etc/fluent/fluentd.backup"
            $SUDO_CMD mv -f /etc/fluent/fluentd.conf /etc/fluent/fluentd.backup
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

    restart_cmd="$SUDO_CMD /etc/init.d/fluentd restart"
    if has_systemd; then
        restart_cmd="$SUDO_CMD systemctl restart fluentd"
        if ! is_td_agent_service_installed; then
            $SUDO_CMD systemctl enable fluentd
        fi
    fi

    if [ $START_SERVICES -eq 0 ]; then
        if is_td_agent_service_installed; then
            printf "\033[32m

Zebrium Log Collector is not started.

To start Log Collector manually, run:
    sudo systemctl start zebrium-container-mon
    sudo systemctl start fluentd

\033[0m"

        else
            printf "\033[32m

Zebrium Log Collector is not started.

To start Log Collector manually, run:
    sudo /etc/init.d/fluentd start

\033[0m"
        fi
        exit 0
    else
        if has_systemd && systemctl -a | grep -q zebrium-container-mon; then
            $SUDO_CMD systemctl start zebrium-container-mon.service
        fi
    fi

    log info "Starting Zebrium log collector..."
    # We have seen systemd returns error on first start of fluentd, so we ignore error and just check
    # status
    set +e
    trap - ERR

    eval $restart_cmd >> $LOG_FILE 2>&1

    if is_td_agent_service_installed; then
        while : ; do
            log info "Waiting for log collector to come up (checking systemctl status fluentd) ..."
            systemctl status fluentd > /dev/null && break
            sleep 5
        done
        printf "\033[32m

Zebrium Log Collector is running.

If you ever want to stop the Log Collector, run:

    sudo systemctl stop zebrium-container-mon
    sudo systemctl stop fluentd

And to run it again run:

    sudo systemctl start zebrium-container-mon
    sudo systemctl start fluentd

\033[0m"

    else
        while : ; do
            log info "Waiting for log collector to come up (checking /etc/init.d/fluentd status) ..."
            $SUDO_CMD /etc/init.d/fluentd status && break
            sleep 5
        done
        printf "\033[32m

Zebrium Log Collector is running.

If you ever want to stop the Log Collector, run:

    sudo /etc/init.d/fluentd stop

And to run it again run:

    sudo /etc/init.d/fluentd start

\033[0m"
    fi
}

main "$@"