# LINUX COLLECTOR DETAILS
Zebrium's fluentd output plugin sends the logs you collect with Fluentd on Linux to Zebrium for automated Anomaly detection.
Our github repository is located [here](https://github.com/zebrium/ze-fluentd-plugin).

For instructions on deploying our fluentd collector for Docker environmens, please see Docker setup [here](https://docs.zebrium.com/docs/setup/docker)

# ze-fluentd-plugin

## Getting Started
### Installing
1. Get Zebrium API server URL and authentication token from [Zebrium](https://www.zebrium.com).
2. Determine what deployment name to use.
3. Run the following command in a shell on host:
```
curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_LOG_COLLECTOR_URL=<ZAPI_URL> ZE_LOG_COLLECTOR_TOKEN=<AUTH_TOKEN> ZE_HOST_TAGS="ze_deployment_name=<deployment_name>" /bin/bash
```
The default system log file paths are defined by the ZE_LOG_PATHS environment variable. Its default value is
```
"/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"
```
The ZE_USER_LOG_PATHS environment variable can be used to add more user specific log file paths. For example, to add app log files at `/app1/log/app1.log` and `/app2/log/\*.log`, you can set ZE_USER_LOG_PATHS to:
```
"/app1/log/app1.log,/app2/log/*.log"
```
## Upgrading
The upgrade command is similar to the installation command:
```
curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_LOG_COLLECTOR_URL=<ZAPI_URL> ZE_LOG_COLLECTOR_TOKEN=<AUTH_TOKEN> ZE_HOST_TAGS="ze_deployment_name=<deployment_name>" OVERWRITE_CONFIG=1 /bin/bash
```
Please note setting `OVERWRITE_CONFIG` to 1 will cause `/etc/td-agent/td-agent.conf` to be upgraded to latest version.
## Uninstalling
```
curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_OP=uninstall /bin/bash
```
## Installing on Hosts with Existing td-agent Configuration

It is possible to add Zebrium output plugin on a host with existing td-agent configuration without running Zebrium log collector installer.
1. Download Zebrium output plugin from `https://github.com/zebrium/ze-fluentd-plugin/releases/download/1.37.2/fluent-plugin-zebrium_output-1.37.2.gem`
2. Run the following command in the same directory where `fluent-plugin-zebrium_output-1.37.2.gem` is saved:
```
sudo td-agent-gem install fluent-plugin-zebrium_output
```
3. Add Zebrium output configuration to `/etc/td-agent/td-ageng.conf`. Below is an example configuration which duplicates log messages and sends one copy to Zebrium.
```
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

## Configuration
The configuration file for td-agent is at `/etc/td-agent/td-agent.conf`.
The following parameters must be configured for your instance:
<table>
  <tr>
    <th>Parameter</th>
    <th>Description</th>
    <th>Note</th>
  </tr>
  <tr>
    <td>ze_log_collector_url</td>
    <td>Zebrium log host URL</td>
    <td>Provided by Zebrium once your account has been created.</td>
  </tr>
  <tr>
    <td>ze_log_collector_token</td>
    <td>Authentication token</td>
    <td>Provided by Zebrium once your account has been created.</td>
  </tr>
  <tr>
    <td>path</td>
    <td>Log files to read</td>
    <td>Both files and file patterns are allowed. Files should be separated by comma. The default value is `"/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"`</td>
  </tr>
  <tr>
    <td>ze_host_tags</td>
    <td>Host meta data</td>
    <td>This parameter is optional. You can pass meta data in key-value pairs, the format is: "key1=value1,key2=value2". We suggest at least set one tag for deployment name: "ze_deployment_name=&lt;your_deployment_name&gt;"</td>
  </tr>
</table>

### User Log Paths
User log paths can be configured via `/etc/td-agent/log-file-map.conf`. During log collector service startup, if `/etc/td-agent/log-file-map.conf` exists, log collector service script writes log paths defined in `/etc/td-agent/log-file-map.conf` to `/etc/td-agent/conf.d/user.conf`. Please note any user log paths configured at installation time via ZE_USER_LOG_PATHS must be added to `/etc/td-agent/log-file-map.conf` to avoid being overwritten.
```
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
### Environment Variables
None
## Usage
### Start/stop Fluentd
Fluentd agent can be started or stopped with the command:
```
sudo systemctl <start | stop> td-agent
```
## Testing your installation
Once the collector has been deployed in your environment, your logs and anomaly detection will be available in the Zebrium UI.
## Troubleshooting
In the event that Zebrium requires the collector logs for troubleshooting, logs are located here:
1. Collector installation log:  `/tmp/zlog-collector-install.log.*`
2. Collector runtime log: `/var/log/td-agent/td-agent.log`
## Contributors
* Brady Zuo (Zebrium)
