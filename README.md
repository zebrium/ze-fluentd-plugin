# ze-fluentd-plugin
Zebrium's fluentd output plugin sends the logs you collect with Fluentd to Zebrium for automated Anomaly detection.
## Features
##### upload
Upload log event data to your Zebrium instance from a file or stream (stdin) with appropriate meta data.
##### def
Show the event-type (eType) definition for structured events in the database.
##### cat
Show events from the database by: meta-data, eType, time range, or first occurrence in CSV, JSON, pretty-print or raw format.
## Getting Started
##### Prerequisites
* Fluentd
##### Installing
1. Install [Fluentd](https://www.fluentd.org/download) and any dependencies.

2. Download/copy Zebrium output plugin package fluent-plugin-zebrium_output-1.0.0.gem.
   1. `git clone https://github.com/zebrium/ze-fluentd-plugin.git`
3. Run the following command in the same directory where pkgs/fluent-plugin-zebrium_output-1.0.0.gem was downloaded.
   1. `td-agent-gem install fluent-plugin-zebrium_output`
## Configuration
The configuration file for td-agent is at `/etc/td-agent/td-agent.conf`.
The following tags `td-agent.conf must` be configured for your instance:
```
ze_log_collector_url "https://YOUR_ZE_API_INSTANCE_NAME.zebrium.com"
ze_log_collector_token "YOUR_API_TOKEN"
ze_tag_branch "branch1"
ze_tag_build "build123"
ze_tag_node "canary-node"
```

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
 ze_log_collector_url "https://zapi02.zebrium.com"
 ze_log_collector_token "12345678910"
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
Use `ze help` for a complete list of command operations and options.
```
ze help
```
## Testing your installation
Use `ze up` to ingest log events into your Zebrium instance.
```
ze up --file=/var/log/messages --node=server01 --log=varlogmsgs
```
Use `ze cat` to show events already ingested into your Zebrium instance.
```
ze cat --lim=20 --fmt=pp
```
## Contributors
* Larry Lancaster (Zebrium)
* Dara Hazeghi (Zebrium)
* Rod Bagg (Zebrium)
