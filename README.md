# zabbix_tsm_template v6.4
Template TSM checks via passive zabbix agent

This repository includes:
- zbx_tsm_template_v6.4.yaml - zabbix server v6.4 template file;
- zbx_tsm_checks.conf - zabbix agent UserParameter configuration file;
- zbx_tsm.sh - bash script with the collection of functions for monitoring IBM TSM instance via passive zabbix agent checks.

The configuration was tested with TSM administrative client 6.2.5, TSM server 6.2.4 on AIX 7.1 and zabbix server 6.4.21.

For the checks to work you need zabbix agent and tsm administrative client (dsmadmc) installed on the monitored host.

Place bash script zbx_tsm.sh to /etc/zabbix/bin and set permissions and owner:
```
chown -R root:zabbix /etc/zabbix/bin
chmod 0750 /etc/zabbix/bin/zbx_tsm.sh
```
Place UserParameter configuration file zbx_tsm_checks.conf to the directory set by option 'Include=' in zabbix_agentd.conf (usually /etc/zabbix/zabbix_agentd.d/) and make sure that zabbix user can read it, then restart zabbix agent service.

Edit configuration variables inside the script zbx_tsm.sh (usually you only need to edit user:pass variables).
```
tmp_dir=/tmp/zbxtsm            # - directory for data files will be created by the script
tsm_binary="/usr/bin/dsmadmc"  # - path to TSM administrative client executable
tsm_user="USER"                # - TSM user id
tsm_pass="PASSWORD"            # - TSM user password
```

A few heavy (long running) lld functions should be added to zabbix agent's user crontab:
```
# Zabbix: TSM lld discovery
0 * * * * /etc/zabbix/bin/zbx_tsm.sh nodedata_cronjob > /dev/null 2>&1
10 * * * * /etc/zabbix/bin/zbx_tsm.sh clisched_cronjob > /dev/null 2>&1
```

Import template file zbx_tsm_template_v6.4.yaml to your zabbix server, then attach the template to the host to be monitored. That's it!
