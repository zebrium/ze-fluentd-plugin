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

function create_config() {
    local CONF_FILE=$TEMP_DIR/td-agent.conf

    if which systemd > /dev/null 2>&1; then
        local SYSTEMD_CONF="$(cat << EOF

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
)"
    fi

    DEFAULT_LOG_PATHS="/var/log/*.log,/var/log/messages,/var/log/syslog,/var/log/secure"
    ZE_LOG_PATHS="${ZE_LOG_PATHS:-${DEFAULT_LOG_PATHS}}"
    cat << EOF > $CONF_FILE
<source>
  @type tail
  path "$ZE_LOG_PATHS"
  format none
  path_key tailed_path
  tag node.logs
  read_from_head true
</source>
$SYSTEMD_CONF

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
    $SUDO_CMD cp -f $CONF_FILE /etc/td-agent/td-agent.conf
}

if [ $(command -v curl) ]; then
    DL_CMD="curl -O -L -f"
    DL_SH_CMD="curl -q -L"
else
    DL_CMD="wget --quiet"
    DL_SH_CMD="wget -qO-"
fi

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
    CODE_NAME=`lsb_release -c | awk '{ print $2 }'`
    echo -e "\033[34m\n* Installing package dependies\n\033[0m\n"
    $SUDO_CMD apt-get update || printf "\033[31m'apt-get update' failed.\033[0m\n"
    $SUDO_CMD apt-get install -y build-essential ruby-dev

    echo -e "\033[34m\n* Installing log collector dependencies\n\033[0m"
    $DL_SH_CMD https://toolbelt.treasuredata.com/sh/install-ubuntu-${CODE_NAME}-td-agent3.sh | sh
else
    echo -e "\033[31mYour OS or distribution are not supported by this install script.\033[0m\n"
    exit;
fi

echo -e "\033[34m\n* Installing fluent-plugin-systemd\n\033[0m"
$SUDO_CMD td-agent-gem install fluent-plugin-systemd
echo -e "\033[34m\n* Uninstalling fluent-plugin-zebrium_output\n\033[0m\n"
$SUDO_CMD td-agent-gem uninstall fluent-plugin-zebrium_output

cd $TEMP_DIR
echo -e "\033[34m\n* Downloading fluent-plugin-zebrium_output\n\033[0m\n"
$DL_CMD https://github.com/zebrium/ze-fluentd-plugin/raw/master/pkgs/fluent-plugin-zebrium_output-1.18.0.gem
echo -e "\033[34m\n* Installing fluent-plugin-zebrium_output\n\033[0m\n"
$SUDO_CMD td-agent-gem install fluent-plugin-systemd fluent-plugin-zebrium_output

TD_DEFAULT_FILE=$DEFAULTS_DIR/td-agent
if [ -e $TD_DEFAULT_FILE ]; then
    if ! grep -q user $TD_DEFAULT_FILE; then
        TD_AGENT_OPTIONS=`grep -oP 'TD_AGENT_OPTIONS=(\K.*)' $TD_DEFAULT_FILE | sed 's/"//g'`
        $SUDO_CMD sh -c "echo TD_AGENT_OPTIONS=\\\"$TD_AGENT_OPTIONS --user root --group root\\\" >> $TD_DEFAULT_FILE"
    fi
else
    $SUDO_CMD sh -c "echo TD_AGENT_OPTIONS=\\\"--user root --group root\\\" >> $TD_DEFAULT_FILE"
fi
if [ -f /var/log/td-agent/td-agent.log ]; then
    $SUDO_CMD chown root:root /var/log/td-agent/td-agent.log
fi

if [ -d /etc/systemd/system ]; then
    $SUDO_CMD mkdir -p /etc/systemd/system/td-agent.service.d
    $SUDO_CMD sh -c '/bin/echo -e "[Service]\nUser=root\nGroup=root\n" > /etc/systemd/system/td-agent.service.d/override.conf'
    $SUDO_CMD systemctl daemon-reload
fi

# Set the configuration
if egrep -q '@type[[:space:]]+zebrium' /etc/td-agent/td-agent.conf 2>/dev/null; then
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
fi
printf "\033[32m

Zebrium Log Collector is running.

If you ever want to stop the Log Collector, run:

    sudo /etc/init.d/td-agent stop

And to run it again run:

    sudo /etc/init.d/td-agent start

\033[0m"
