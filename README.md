# ze-fluentd-plugin
Zebrium's fluentd output plugin sends the logs you collect with Fluentd to Zebrium for automated Anomaly detection.
<!--
## Features
-->
## Getting Started
##### Installing
1. Get Zebrium API server URL and authentication token from [Zebrium](https://www.zebrium.com).
2. Determine what deployment name to use.
3. Run the following command in a shell on host:
   `curl https://raw.githubusercontent.com/zebrium/ze-fluentd-plugin/master/install_collector.sh | ZE_LOG_COLLECTOR_URL=<ZAPI_URL> ZE_LOG_COLLECTOR_TOKEN=<AUTH_TOKEN> ZE_HOST_TAGS="ze_deployment_name=<deployment_name>" /bin/bash`

ZE_LOG_PATHS environment variables can be used to add more log file paths. The default log file paths is `"/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"`. For example, to add app log file at /app1/log/app1.log, you can set the environment variable value to `"/app1/log/app1.log,/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"`

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
    <td>Both files and file patterns are allowed. Files should be separated by comma. The default value is `"/var/log/*.log,/var/log/syslog,/var/log/messages,/var/log/secure"`
  </tr>
  <tr>
    <td>ze_host_tags</td>
    <td>Host meta data</td>
    <td>This parameter is optional. You can pass meta data in key-value pairs, the format is: "key1=value1,key2=value2". We suggest at least set one tag for deployment name: "ze_deployment_name=<your_deployment_name>".
  </tr>
</table>

##### Environment Variables
None
## Usage
##### Start/stop Fluentd on CentOS 7/Ubuntu 16.04/18.04
Fluentd agent can be started or stopped with the command:
```
sudo systemctl <start | stop> td-agent
```
##### Start/stop Fluentd on CentOS 6
On CentOS 6, Fluentd agent can be started or stopped with the command:
```
sudo /etc/init.d/td-agent <start | stop>
```

## Testing your installation
Once the collector has been deployed in your environment, your logs and anomaly detection will be available in the Zebrium UI.
## Contributors
* Brady Zuo (Zebrium)
