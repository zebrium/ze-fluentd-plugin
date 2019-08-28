# ze-fluentd-plugin
Zebrium's fluentd output plugin sends the logs you collect with Fluentd to Zebrium for automated Anomaly detection.
<!--
## Features
-->
## Getting Started
##### Prerequisites
* Fluentd
##### Installing
1. Install [Fluentd](https://www.fluentd.org/download) and any dependencies. See details below
2. Download/copy Zebrium output plugin package fluent-plugin-zebrium_output-1.0.0.gem.
   1. `git clone https://github.com/zebrium/ze-fluentd-plugin.git`
3. Run the following command in the same directory where pkgs/fluent-plugin-zebrium_output-1.0.0.gem was downloaded.
   1. `td-agent-gem install fluent-plugin-zebrium_output`

##### Installing on CentOS 6/Centos 7 (Process should be similar for other flavors of Linux)
1. Log in as root
2. Install packages required by Fluentd and plugins:
   1. `yum -y install gcc ruby-devel rubygems compass`
3. Install Fluentd agent:
   1. `curl -L https://toolbelt.treasuredata.com/sh/install-redhat-td-agent3.sh | sh`
4. Download/copy Zebrium output plugin package fluent-plugin-zebrium_output-1.0.0.gem.
   1. `git clone https://github.com/zebrium/ze-fluentd-plugin.git`
5. Run the following command in the same directory where pkgs/fluent-plugin-zebrium_output-1.0.0.gem was downloaded.
   1. `td-agent-gem install fluent-plugin-zebrium_output`

##### Installing on Ubuntu 16.04/18.04
1. Log in as root
2. Install packages required by Fluentd and plugins:
   1. `apt-get install build-essential ruby-dev`
3. Install Fluentd agent:
   1. For Ubuntu 16.04:
      1. `curl -L https://toolbelt.treasuredata.com/sh/install-ubuntu-xenial-td-agent3.sh | sh`
   2. For Ubuntu 18.04:
      1. `curl -L https://toolbelt.treasuredata.com/sh/install-ubuntu-bionic-td-agent3.sh | sh`
4. Download/copy Zebrium output plugin package fluent-plugin-zebrium_output-1.0.0.gem.
   1. `git clone https://github.com/zebrium/ze-fluentd-plugin.git`
5. Run the following command in the same directory where pkgs/fluent-plugin-zebrium_output-1.0.0.gem was downloaded.
   1. `td-agent-gem install fluent-plugin-zebrium_output`

## Configuration
The configuration file for td-agent is at `/etc/td-agent/td-agent.conf`.
The following tags must be configured for your instance:
<table>
  <tr>
    <th>Tag</th>
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
    <td>ze_tag_branch</td>
    <td>User application software branch</td>
    <td>You should choose a word that uniquely identifies the branch. If you do not have the concept of branch, you can use &quot;-&quot; or any other label.</td>
  </tr>
  <tr>
    <td>ze_tag_build</td>
    <td>User application software build ID</td>
    <td>You should use a word that uniquely identifies the build. If you do not have the concept of build, you can use &quot;-&quot; or any other label.</td>
  </tr>
  <tr>
    <td>ze_tag_node</td>
    <td>Node where collector is running</td>
    <td>This parameter is optional. By default it is read from /etc/hostname or from the hostname command output. The value should be unique.</td>
  </tr>
</table>

Below is an example `/etc/td-agent/td-agent.conf` file with configuration parameters for the Zebrium output plugin. 
##### Setup
```
<source>
 @type tail
 path "/var/log/messages,/var/log/secure"
 format none
 path_key tailed_path
 tag node.logs
</source>
<match **>
 @type zebrium
 ze_log_collector_url "https://YOUR_ZE_API_INSTANCE_NAME.zebrium.com"
 ze_log_collector_token "YOUR_ZE_API_AUTH_TOKEN"
 ze_tag_branch "branch1"
 ze_tag_build "build123"
 ze_tag_node "canary-node"
 @log_level "info"
 <buffer tag>
   @type file
   path /var/log/td-agent/buffer/out_zebrium.*.buffer
   flush_mode "interval"
   flush_interval "60s"
 </buffer>
</match>
```
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
##### Run Fluentd Agent as root User
By default, td-agent is run as td-agent user which does not have permission to read any files. Depending on what log files to be read, you may see "permission denied" error message in /var/log/td-agent/td-agent.log. To fix that issue, you can either change file permission, or run td-agent as root.

* On CentOS 6, edit /etc/init.d/td-agent file, change "TD_AGENT_USER" and "TD_AGENT_GROUP" to "root", and restart td-agent.

* On CentOS7, edit /usr/lib/systemd/system/td-agent.service, change "User" and "Group" configs to "root", and restart td-agent.
## Testing your installation
Once the collector has been deployed in your environment, your logs and anomaly detection will be available in the Zebrium UI.
## Contributors
* Brady Zuo (Zebrium)
