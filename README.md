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
3. Run the following command in the same directory where fluent-plugin-zebrium_output-1.0.0.gem was downloaded.
   1. `td-agent-gem install fluent-plugin-zebrium_output`
## Configuration
The configuration file for td-agent is at `/etc/td-agent/td-agent.conf`.

Below is an example configuration file with configuration parameters for the Zebrium output plugin. 
##### Setup
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
