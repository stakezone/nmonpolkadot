# nmonpolkadot

A complete log file based Polkadot validator uptime monitoring solution for Zabbix. It consists of the shell script nmon.sh for generating log files on the host and the template zbx_5_template_nmonpolkadot.xml for a Zabbix 5.x server. Also useful for other monitoring platforms (with log exporter) and as a tool.

### Concept

nmon.sh generates human-readable logs that look like:

`
[2021-01-14 17:43:18+00:00] status=synced height=5772376 elapsed=6 behind=0 peers=46 session=9912 authoredBlocks=0 heartbeat=waiting`
 
`
[2021-01-14 17:44:01+00:00] status=synced height=5772382 elapsed=7 behind=1 peers=46 session=9912 authoredBlocks=1 heartbeat=waiting`
 
`
[2021-01-14 17:44:43+00:00] status=synced height=5772390 elapsed=7 behind=0 peers=45 session=9912 authoredBlocks=1 heartbeat=ok`

The log line entries that are imported by the server are:

* **status** can be {scriptstarted | synced | catchingup | error} 'error' can have various causes, typically the `polkadot` process is down.
* **height** current height
* **elapsed** time in seconds since current height (useful for latency or chain halt detection)
* **behind** difference between highest and current height
* **peers** number of peers
* **session** the current session 
* **authoredBlocks** (only if validator address is configured) authored blocks from the configured validator address for the current session
* **heartbeat** (only if validator address is configured) can be {waiting | ok | missing | missing_ip} 'waiting' if heartbeat-after-height is not yet reached for current session, 'ok' if either a block was authored or a heartbeat sent upon heartbeat-after-height, 'missing' heartbeat was not sent, 'missing_ip' heartbeat message does not contain the ip of the local node (useful for confirming local node)

### Installation

The script for the host has a configuration section on top where parameters can be set. There is also information for the required dependencies and how to install the JS-API.

A Zabbix server is required that connects to the host running the Solana validator. On the host side the Zabbix agent needs to be installed and configured for active mode. There is various information on the Zabbix site and from other sources that explains how to connect a host to the server and utilize the standard Linux OS templates for general monitoring. Once these steps are completed the Solana Validator template file can be imported. Under `All templates/Template App Polkadot` there is a `Macros` section with several parameters that can be configured, in particular the path to the log file must be set. Do not change those values there, instead go to `Hosts` and select the particular host, then go to `Macros`, then to `Inherited and host macros`. There the macros from the generic template are mirrored for the specific host and can be set without affecting other hosts using the same template.
