# LINUX COLLECTOR DETAILS

Zebrium's linux log collector sends the logs you collect with [fluentd](https://www.fluentd.org/) on linux to Zebrium for automated anomaly detection.
Our github repository is located [here](https://github.com/zebrium/ze-fluentd-plugin).  Zebium's linux log collector leverages our [fluentd output plugin](https://github.com/zebrium/fluentd-output-zebrium) and is distributed leveraging td-agent version 4.  Because of this, we are limited to the installation platforms that are supported by the td-agent installation.  For more information, see the package [documentation](https://www.fluentd.org/download/td_agent).  Below are instructions on utilizing our installation script for installing and configuring td-agent alongside our plugins.

For instructions on deploying our fluentd collector for [docker](https://github.com/zebrium/fluentd-output-zebrium) environments, please see docker setup [here](https://docs.zebrium.com/docs/setup/docker)

## Installation and Configuration

Below is the installation and configuration instructions for the zebrium log collector.  The default configuration will collect any logs inside of `/var/log/*.log` and send them to Zebrium.  For advanced configuration and usages, please see the relevant section [here](#advanced-configurations).

### System Requirements

The following OS distributions are supported:

DEB Packages:

1. Ubuntu: Jammy, Focal, Bionic, Xenial
2. Debian: Bullseye, Buster

RPM Package:

1. CentOS/RHEL 7/8/9
2. Oracle Linux 7/8/9
3. Amazon Linux 2

### Installing

1. If the environment uses a proxy server please the section "Operation with a Proxy Server" below.
2. Get Zebrium API server URL and authentication token from [Zebrium](https://www.zebrium.com).
3. Determine what deployment name to use.
4. Run the following command in a shell on host:

   ``` bash
   curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_LOG_COLLECTOR_URL=<ZAPI_URL> ZE_LOG_COLLECTOR_TOKEN=<AUTH_TOKEN> ZE_HOST_TAGS="ze_deployment_name=<deployment_name>" /bin/bash
   ```

   The default system log file paths are defined by the ZE_LOG_PATHS environment variable. Its default value is

   ``` bash
   "/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"
   ```

   The ZE_USER_LOG_PATHS environment variable can be used to add more user specific log file paths. For example, to add app log files at `/app1/log/app1.log` and `/app2/log/\*.log`, you can set ZE_USER_LOG_PATHS to:

   ``` bash
   "/app1/log/app1.log,/app2/log/*.log"
   ```

### Upgrading

The upgrade command is similar to the installation command:

``` bash
curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_LOG_COLLECTOR_URL=<ZAPI_URL> ZE_LOG_COLLECTOR_TOKEN=<AUTH_TOKEN> ZE_HOST_TAGS="ze_deployment_name=<deployment_name>" OVERWRITE_CONFIG=1 /bin/bash
```

Please note setting `OVERWRITE_CONFIG` to 1 will cause `/etc/td-agent/td-agent.conf` to be upgraded to latest version.

### Uninstalling

``` bash
curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_OP=uninstall /bin/bash
```

### Installing on Hosts with Existing fluent Configuration

It is possible to add Zebrium output plugin on a host with existing fluent configuration without running Zebrium log collector installer.  Zebrium output plugin is provided through RubyGems [here](https://rubygems.org/gems/fluent-plugin-zebrium_output)

1. Run the following command:

   ``` bash
   sudo td-agent-gem install fluent-plugin-zebrium_output
   ```

3. Add Zebrium output configuration to `/etc/fluent/fluent.conf`. Below is an example configuration which duplicates log messages and sends one copy to Zebrium.

   ``` bash
   <match **>
     @type copy
     # Zebrium log collector
     <store>
       @type zebrium
       ze_log_collector_url "ZE_LOG_COLLECTOR_URL"
       ze_log_collector_token "ZE_LOG_COLLECTOR_TOKEN"
       ze_host_tags "ze_deployment_name=#{Socket.gethostname},myapp=test2"
       @log_level "info"
       <buffer tag>
         @type file
         path "/var/td-agent/zebrium"
         flush_mode "interval"
         flush_interval "60s"
       </buffer>
     </store>
     <store>
         @type OTHER_OUTPUT_PLUGIN
         ...
     </store>
   </match>
   ```

### Configurations

There are several configurations options for the log collector. The configuration file for td-agent is at `/etc/td-agent/td-agent.conf`.

#### Parameters

The following parameters must be configured for your instance:
| Parameter | Description | Note |
| ----------| ----------| ----------|
| ze_log_collector_url | Zebrium log host URL | Provided by Zebrium once your account has been created.|
| ze_log_collector_token | Authentication token | Provided by Zebrium once your account has been created.|
| path | Log files to read | Both files and file patterns are allowed. Files should be separated by comma. The default value is `"/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"`|
| ze_host_tags|Host meta data | This parameter is optional. You can pass meta data in key-value pairs, the format is: "key1=value1,key2=value2". We suggest at least set one tag for deployment name: "ze_deployment_name=&lt;your_deployment_name&gt;"|
| ze_host_in_logpath | Log path component for remote host name | This parameter is optional. For situations where a remote host name is embedded in the log file directory path structure, e.g. "/var/log/remote/&lt;host&gt;/...", this can be used as the originating host for the log by setting this parameter to the path component to be used for the hostname. The value should be an integer, 1-based. In this example the configuration would be "ze_host_in_logpath=4".|
| ze_forward_tag | Tag to specify log-forwarded sources | This parameter is optional. It can be used to indicate sources that are being used for remote log forwarding, by specifying a specific fluentd "tag" to one or more sources.  The default tag value is "ze_forwarded_logs".|
| ze_path_map_file| Path mapping file | This parameter is optional. It allows embedded semantic data (ids, tags,configs) in logfile paths to be parsed and added to Zebrium log data. Set to the full path of a JSON file containing mapping information. Default is empty string. See below under Log Path Mapping|

#### Advanced Configurations

##### User Log Paths

In some configurations, you may wish to create a dynamic configuration from a file to be loaded on the start of td-agent.  This can be accomplished by creating a log-file-map.conf json file as seen below.  This file will need to reside in the following location `/etc/td-agent/log-file-map.conf`. During log collector service startup, if `/etc/td-agent/log-file-map.conf` exists, log collector service script writes log paths defined in `/etc/td-agent/log-file-map.conf` to `/etc/td-agent/conf.d/user.conf`.

Please note any user log paths configured at installation time via ZE_USER_LOG_PATHS must be added to `/etc/td-agent/log-file-map.conf` to avoid being overwritten.

``` json
{
  "mappings": [
    {
      "file": "/app1/log/error.log",
      "alias": "app1_error"
    },
    {
      "file": "/app2/log/error.log",
      "alias": "app2_error"
    },
    {
      "file": "/var/log/*.log",
      "exclude": "/var/log/my_debug.log,/var/log/my_test.log"
    }
  ]
}
```

##### Filtering Specific Log Events

If you wish to exclude certain sensitive or noisy events from being sent to Zebrium, you can filter them at the source collection point by doing the following:

1. Add the following in /etc/td-agent/td-agent.conf after other "@include":

   ``` configuration
   @include conf.d/log_msg_filters.conf
   ```

2. Create a config file /etc/td-agent/conf.d/log_msg_filters.conf containing:

   ``` configuration
   <filter TAG_FOR_LOG_FILE>
     @type grep
     <exclude>
       key message
       pattern /<PATTERN_FOR_LOG_MESSAGES>/
   </exclude>
   </filter>
   ```

3. Restart td-agent: sudo systemctl restart td-agent

###### Example

Below is an example `log_msg_filters.conf` for filtering out specific messages from a Vertica log file at `/fast1/vertica_catalog/zdb/v_zdb_node0001_catalog/vertica.log`

In this example, the Fluentd tag for file is node.logs.<FILE_NAME_REPLACE_/_WITH_DOT> (i.e replace all slashes with dots in the file path).

``` configuration
<filter node.logs.fast1.vertica_catalog.zdb.v_zdb_node0001_catalog.vertica.log>
  @type grep
  <exclude>
    key message
    pattern /^[^2]|^.[^0]|TM Merge|Authenticat|[Ll]oad *[Bb]alanc[ei]|\[Session\] <INFO>|\[Catalog\] <INFO>|\[Txn\] <INFO>|Init Session.*<LOG>/
  </exclude>
</filter>
```

##### Log Path Mapping

Log path mapping allows semantic information (ids, configs and tags) to be extracted from log paths
and passed to the Zebrium backend. For example, log-file specific host information or business-related
tags that are embedded in the path of the log file can be extracted..

Log path mapping is configured using a JSON file, with format:

``` json
{
  "mappings": {
    "patterns": [
      "regex1", ...
    ],
    "tags": [
      "tag_name", ...
    ],
    "ids": [
      "id_name",...
    ],
    "configs": [
       "config_name",...
    ]
  }
}
```
##### Configuring Multiple Zebrium Service Groups Within a Single Collector

It is possible to use a single td-agent to send log files to multiple Zebrium service groups. Knowlege about advanced fluentd configuration is required. It is recommended to review the official documentation at https://docs.fluentd.org/configuration/config-file 

The following are required:
- each service group needs to have its own source block and match block defenitions
- in each source block, the path should be as specific as possible
- paths in source blocks should not overlap
- each source block needs a unique pos_file (td-agent will create the file if it does not exist)
- each source block should include a unique tag to specify which match block/service group should pick up the log events
- each match block should match on the tag in its corresponding source block
- ze_log_collector_url, ze_log_collector_token, and ze_log_collector_type will probably be the same in all match blocks
- ze_host_tags specifies the service group name with "ze_deployment_name=<service group name>"
- each match block requires a unique buffer path, which will be created if the specified path does not exist

Here's an example of how this could be configured in /etc/td-agent/td-agent.conf:
```
<source>
  @type tail
  path "/var/log/auth.log"
  format none
  path_key tailed_path
  pos_file /var/log/td-agent/position_file_1.pos
  tag seamus1
  read_from_head true
</source>

<source>
  @type tail
  path "/var/log/syslog"
  format none
  path_key tailed_path
  pos_file /var/log/td-agent/position_file_2.pos
  tag seamus2
  read_from_head true
</source>

@include conf.d/user.conf
@include conf.d/containers.conf
@include conf.d/systemd.conf

<match seamus1>
  @type zebrium
  ze_log_collector_url "https://trial.zebrium.com"
  ze_log_collector_token "<your token here>"
  ze_log_collector_type "linux"
  ze_host_tags "ze_deployment_name=seamusfirstservicegroup"
  <buffer tag>
    @type file
    path /var/log/td-agent/buffer1/out_zebrium.*.buffer
    chunk_limit_size "1MB"
    chunk_limit_records "4096"
    flush_mode "interval"
    flush_interval "60s"
  </buffer>
</match>

<match seamus2>
  @type zebrium
  ze_log_collector_url "https://trial.zebrium.com"
  ze_log_collector_token "<your token here, should be the same as above>"
  ze_log_collector_type "linux"
  ze_host_tags "ze_deployment_name=seamussecondservicegroup"
  <buffer tag>
    @type file
    path /var/log/td-agent/buffer2/out_zebrium.*.buffer
    chunk_limit_size "1MB"
    chunk_limit_records "4096"
    flush_mode "interval"
    flush_interval "60s"
  </buffer>
</match>
```



Set "patterns" to regular expressions to match the log file path. Each regex named capture in a matching regular expression will be compared to the "tags", "ids" and "configs" sections and added to the corresponding record section(s).
Use the ze_path_map_file configuration parameter to specify the path to the JSON file.

##### Proxy Configuration

If the agent environment requires a non-transparent proxy server to be configured this should be done at two points:

* The standard http\_proxy and https\_proxy environment variables must be set in the local environment when the installer is run. This allows the installer to access the Internet to download necessary components.

* After installation is run the system service also needs to have the same environment variables available. This allows the Zebrium agent to communicate with the log host to send logs.

###### Setting proxy server in a systemd environment

If the agent service is run from systemd and a proxy server is in use, the service needs to have the appropriate proxy configuration added to systemd. (This may not be needed if your system is already configured so that all systemd services globally use a proxy.) To do this, after the installation is performed edit the file /etc/systemd/service/td-agent.service.d/override.conf to add environment configuration lines for the proxy server, for example:

``` bash
Environment=http_proxy=myproxy.example.com:8080
```

After this is done the systemd daemon should be reloaded, and then the service started:

``` bash
sudo systemctl daemon-reload

sudo systemctl restart td-agent
```

## Usage

### Start/stop Fluentd

Fluentd agent can be started or stopped with the command:

``` bash
sudo systemctl <start | stop> td-agent
```

## Testing your installation

Once the collector has been deployed in your environment, your logs and anomaly detection will be available in the Zebrium UI.

## Troubleshooting

In the event that Zebrium requires the collector logs for troubleshooting, logs are located here:

1. Collector installation log:  `/tmp/zlog-collector-install.log.*`

2. Collector runtime log: `/var/log/td-agent/td-agent.log`

In case of an HTTP connection error, please check the spelling of the Zebrium host URL. Also check that any network proxy servers are configured appropriately.

Please contact Zebrium Support at <support@zebrium.com> if you need any assistance.  When reaching out to support, please be sure to include the following information
and files to more efficiently resolve your issue.

1. Description of the problem and relevant environment specific information
2. Collector installation log:  `/tmp/zlog-collector-install.log.*`
3. Collector runtime log: `/var/log/td-agent/td-agent.log`
4. Collector configurations: `/etc/td-agent/td-agent.conf`, `/etc/td-agent/conf.d/*.conf`
