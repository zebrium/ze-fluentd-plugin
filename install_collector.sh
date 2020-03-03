#!/bin/bash
# (C) Zebrium, Inc. 2019
# All rights reserved
# Licensed under Simplified BSD License (see LICENSE)
# Zebrium Log Collector installation script: install and set up the log collector.

set -e
LOG_FILE="zlog-collector-install.log"

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

Please send an email to support@zebrium.com with the contents of zlog-collector-install.log
and we'll do our very best to help you solve your problem.\n\033[0m\n"
    cleanup
}

function update_td_agent_service_file() {
    if ! grep -q 'ExecStartPre=' /lib/systemd/system/td-agent.service; then
        printf "\033[34m* Add ExecStartPre script for td-agent service\n\033[0m\n"
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
        echo -e "\033[34m\n* Systemd detected, creating systemd config\n\033[0m"
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
    tag systemd.service.$1
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
  tag containers.*
  format json
  time_format %Y-%m-%dT%H:%M:%S.%NZ
  utc true
</source>
EOF

    $SUDO_CMD cp -f $MAIN_CONF_FILE /etc/td-agent/td-agent.conf
    $SUDO_CMD mkdir -p /etc/td-agent/conf.d
    $SUDO_CMD cp -f $USER_CONF_FILE /etc/td-agent/conf.d
    $SUDO_CMD cp -f $CONTAINERS_CONF_FILE /etc/td-agent/conf.d
    if [ -n "$SYSTEMD_INCLUDE" ]; then
        $SUDO_CMD cp -f $SYSTEMD_CONF_FILE /etc/td-agent/conf.d
    fi
}

if [ $(command -v curl) ]; then
    DL_CMD="curl --connect-timeout 30 --retry 3 --retry-delay 5 -O -L -f"
    DL_SH_CMD="curl --connect-timeout 30 --retry 3 --retry-delay 5 -q -L"
else
    DL_CMD="wget --quiet --dns-timeout=30 --connect-timeout=30"
    DL_SH_CMD="wget --dns-timeout=30 --connect-timeout=30 -qO-"
fi

OVERWRITE_CONFIG=${OVERWRITE_CONFIG:-0}
START_SERVICES=${START_SERVICES:-1}

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

if [ -z "$ZE_LOG_COLLECTOR_URL" ]; then
    err_exit "ZE_LOG_COLLECTOR_URL environment variable is not set"
fi
if [ -z "$ZE_LOG_COLLECTOR_TOKEN" ]; then
    err_exit "ZE_LOG_COLLECTOR_TOKEN environment variable is not set"
fi

# OS/Distro Detection
# Try lsb_release, fallback with /etc/issue then uname command
KNOWN_DISTRIBUTION="(Debian|Ubuntu|RedHat|CentOS|Amazon)"
DISTRIBUTION=$(lsb_release -d 2>/dev/null | grep -Eo $KNOWN_DISTRIBUTION  || grep -Eo $KNOWN_DISTRIBUTION /etc/issue 2>/dev/null || grep -Eo $KNOWN_DISTRIBUTION /etc/Eos-release 2>/dev/null || grep -m1 -Eo $KNOWN_DISTRIBUTION /etc/os-release 2>/dev/null || uname -s)

if [ $DISTRIBUTION = "Darwin" ]; then
    printf "\033[31mMac is not supported.\033[0m\n"
    exit 1;

elif [ -f /etc/debian_version -o "$DISTRIBUTION" == "Debian" -o "$DISTRIBUTION" == "Ubuntu" ]; then
    OS="Debian"
elif [ -f /etc/redhat-release -o "$DISTRIBUTION" == "RedHat" -o "$DISTRIBUTION" == "CentOS" -o "$DISTRIBUTION" == "Amazon" ]; then
    OS="RedHat"
# Some newer distros like Amazon may not have a redhat-release file
elif [ -f /etc/system-release -o "$DISTRIBUTION" == "Amazon" ]; then
    OS="RedHat"
fi

# Root user detection
if [ $(echo "$UID") = "0" ]; then
    SUDO_CMD=''
else
    SUDO_CMD='sudo'
fi

# Install the Fluentd, plugin and their depedencies
if [ $OS = "RedHat" ]; then
    DEFAULTS_DIR=/etc/sysconfig
    TD_AGENT_INSTALLED=$(yum list installed td-agent > /dev/null 2>&1 || echo "no")
    if [ "$TD_AGENT_INSTALLED" == "no" ]; then
        echo -e "\033[34m\n* Installing log collector dependencies\n\033[0m"
        $SUDO_CMD yum -y install gcc ruby-devel rubygems
        $DL_SH_CMD https://toolbelt.treasuredata.com/sh/install-redhat-td-agent3.sh | sh
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
    FLAVOR_STR=""
    if [ $IS_UBUNTU -ge 1 ]; then
        FLAVOR_STR="ubuntu"
    else
        FLAVOR_STR="debian"
    fi

    echo -e "\033[34m\n* Installing package dependies\n\033[0m\n"
    $SUDO_CMD apt-get update || printf "\033[31m'apt-get update' failed.\033[0m\n"
    $SUDO_CMD apt-get install -y build-essential ruby-dev

    echo -e "\033[34m\n* Installing log collector dependencies\n\033[0m"
    $DL_SH_CMD https://toolbelt.treasuredata.com/sh/install-${FLAVOR_STR}-${CODE_NAME}-td-agent3.sh | sh
else
    echo -e "\033[31mYour OS or distribution are not supported by this install script.\033[0m\n"
    exit;
fi

echo -e "\033[34m\n* Installing fluent-plugin-systemd\n\033[0m"
$SUDO_CMD td-agent-gem install fluent-plugin-systemd
echo -e "\033[34m\n* Installing docker-api\n\033[0m"
$SUDO_CMD td-agent-gem install docker-api
echo -e "\033[34m\n* Uninstalling fluent-plugin-zebrium_output\n\033[0m\n"
$SUDO_CMD td-agent-gem uninstall fluent-plugin-zebrium_output

cd $TEMP_DIR
echo -e "\033[34m\n* Downloading fluent-plugin-zebrium_output\n\033[0m\n"
$DL_CMD https://github.com/zebrium/ze-fluentd-plugin/raw/master/pkgs/fluent-plugin-zebrium_output-1.20.0.gem
echo -e "\033[34m\n* Installing fluent-plugin-zebrium_output\n\033[0m\n"
$SUDO_CMD td-agent-gem install fluent-plugin-systemd fluent-plugin-zebrium_output

echo -e "\033[34m\n* Downloading zebrium-fluentd package\n\033[0m\n"
$DL_CMD https://github.com/zebrium/ze-fluentd-plugin/raw/master/pkgs/zebrium-fluentd-1.18.0.tgz
echo -e "\033[34m\n* Installing zebrium-fluentd\n\033[0m\n"
$SUDO_CMD tar -C /opt -xf zebrium-fluentd-1.18.0.tgz

TD_DEFAULT_FILE=$DEFAULTS_DIR/td-agent
if [ ! -e $TD_DEFAULT_FILE ]; then
    $SUDO_CMD sh -c "echo TD_AGENT_USER=root >> $TD_DEFAULT_FILE"
    $SUDO_CMD sh -c "echo TD_AGENT_GROUP=root >> $TD_DEFAULT_FILE"
fi
if [ -f /var/log/td-agent/td-agent.log ]; then
    $SUDO_CMD chown root:root /var/log/td-agent/td-agent.log
fi

if [ -d /etc/systemd/system ]; then
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
    echo -e "\033[34m\n* Keeping old /etc/td-agent/td-agent.conf configuration file\n\033[0m\n"
else
    if [ -e /etc/td-agent/td-agent.conf ]; then
        echo -e "\033[34m\n* Saving current /etc/td-agent/td-agent.conf to /etc/td-agent/td-agent.backup\n\033[0m\n"
        $SUDO_CMD mv -f /etc/td-agent/td-agent.conf /etc/td-agent/td-agent.backup
    fi
    echo -e "\033[34m\n* Creating new fluentd config and adding API server URL and API key\n\033[0m\n"
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
if [ -e /etc/systemd/system ]; then
    restart_cmd="$SUDO_CMD systemctl restart td-agent"
    if ! systemctl -a | grep td-agent; then
        $SUDO_CMD systemctl enable td-agent
    fi
fi

if [ $START_SERVICES -eq 0 ]; then
    if which systemctl > /dev/null 2>&1 && systemctl -a | grep -q td-agent; then
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
    if which systemctl > /dev/null 2>&1 && systemctl -a | grep -q zebrium-container-mon; then
        $SUDO_CMD systemctl start zebrium-container-mon.service
    fi
fi

printf "\033[34m* Starting Zebrium log collector...\n\033[0m\n"
# We have seen systemd returns error on first start of td-agent, so we ignore error and just check
# status
set +e
trap - ERR

eval $restart_cmd >> $LOG_FILE 2>&1

if which systemctl > /dev/null 2>&1 && systemctl -a | grep -q td-agent; then
    while : ; do
        echo -e "\033[34m* Waiting for log collector to come up ...\n\033[0m\n"
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
        echo -e "\033[34m* Waiting for log collector to come up ...\n\033[0m\n"
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
