# zabbix_tsm_template v6.4
Template TSM checks via passive zabbix agent

This is collection of zabbix v6.4 template, zabbix agent config and bash script, that will allow you to monitor IBM TSM instance via passive agent checks.
For the checks to work you need zabbix agent and tsm administrative client (dsmadmc).
This configuration was tested with TSM 6.3 and zabbix server 6.4.21.

Place bash script zbx_tsm.sh to /etc/zabbix/bin and set permissions and owner: 
chmod 0750 /etc/zabbix/bin/zbx_tsm.sh
chown root:zabbix /etc/zabbix/bin/zbx_tsm.sh

Make sure the directory /etc/zabbix/bin is included in main zabbix agent configuration file (/etc/zabbix/zabbix_agent.conf),
Place config file tsm_checks.cfg to the directory with optional configuration files (usually /etc/zabbix/zabbix_agent.d/), make sure that zabbix user can read it, then restart zabbix agent service.

Edit configuration variables inside the script zbx_tsm.sh (usually you only need to edit user:password variables to connect to TSM with administrative client).

Import template zabbix_tsm_template_v6.4.yaml to your zabbix server, then atach the template to the host to be monitored.

