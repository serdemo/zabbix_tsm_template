#!/usr/bin/bash
# Description: Collection of functions to perform passive checks on TSM server via zabbix agent
# Tested with dsmadmc 6.2.5 and TSM server 6.2.4 on AIX 7.1
# For security reasons avoid using TSM account with administrative privileges. A simple 'client owner' account is enough.
# This script is inspired by the folowing projects:
# - https://github.com/rollercow/tsm_zabbix/tree/master
# - https://github.com/thobiast/tsmmonitor

#################
# CONFIGURATION #
#################
tmp_dir=/tmp/zbxtsm                                                 # - directory for data files, it will be created by the script
tsm_binary="/usr/bin/dsmadmc"                                       # - path to TSM administrative client executable
tsm_user="USER"                                                     # - TSM user id
tsm_pass="PASS"                                                     # - TSM user password
internal_tsmserver_name=$("$tsm_binary" -id=$tsm_user -pa=$tsm_pass -dataonly=yes -displaymode=list q status | grep 'Server Name' | awk -F ':' '{print $2}' | xargs)
[[ -z $internal_tsmserver_name ]] && internal_tsmserver_name="TSM"  # - change this asignment according to your environment

# PREREQUISITES CHECKS
[[ ! `which "which" 2>/dev/null` ]] && echo "This script requres: which" && exit 1
[[ ! `which "bash" 2>/dev/null` ]] && echo "This script requres: bash" && exit 1
[[ ! `which "$tsm_binary" 2>/dev/null` ]] && echo "This script requres: $tsm_binary" && exit 1
[[ ! `which "grep" 2>/dev/null` ]] && echo "This script requres: grep" && exit 1
[[ ! `which "xargs" 2>/dev/null` ]] && echo "This script requres: xargs" && exit 1
[[ ! `which "wc" 2>/dev/null` ]] && echo "This script requres: wc" && exit 1
[[ ! `which "awk" 2>/dev/null` ]] && echo "This script requres: awk" && exit 1
[[ ! `which "sed" 2>/dev/null` ]] && echo "This script requres: sed" && exit 1
[[ ! `which "tr" 2>/dev/null` ]] && echo "This script requres: tr" && exit 1
[[ ! `which "cut" 2>/dev/null` ]] && echo "This script requres: cut" && exit 1
[[ ! `which "sort" 2>/dev/null` ]] && echo "This script requres: sort" && exit 1
[[ ! `which "cat" 2>/dev/null` ]] && echo "This script requres: cat" && exit 1
[[ ! `which "echo" 2>/dev/null` ]] && echo "This script requres: echo" && exit 1
[[ ! `which "tail" 2>/dev/null` ]] && echo "This script requres: tail" && exit 1
[[ ! `which "head" 2>/dev/null` ]] && echo "This script requres: head" && exit 1
[[ ! -d "$tmp_dir" ]] && mkdir -p "$tmp_dir" 2>/dev/null
[[ ! -d "$tmp_dir" ]] && echo "error creating directory: $tmp_dir" && exit 1


#################
#  FUNCTIONS    #
#################

# TSM commands execution function
function tsm_cmd {
	"$tsm_binary" -id=$tsm_user -pa=$tsm_pass -dataonly=yes "$@" | grep -Ev 'ANS0102W|ANS2036W' # shuts up persistent warning
}

# LLD discovery and other agent check functions
function discover_path {
	local TSM_STATS=${tmp_dir}/zbxtsm_path_stats.txt
	PATH_STATS=$TSM_STATS
	local x
	tsm_cmd -tab -displaymode=table q path > $TSM_STATS
}

function discover_libvol {
	local TSM_STATS=${tmp_dir}/zbxtsm_libvol_stats.txt
	LIBV_STATS=$TSM_STATS
	local x
	tsm_cmd -tab -displaymode=table q libv > $TSM_STATS
}

function discover_vol {
	local TSM_STATS=${tmp_dir}/zbxtsm_vol_stats.txt
	VOL_STATS=$TSM_STATS
	local x
	tsm_cmd -tab -displaymode=table q vol f=d > $TSM_STATS
	# for reference:
	# $1 - Volume Name
	# $2 - Storage Pool Type
	# $8 - Access
	# $11 - In Error State
	# $13 - Number of Times Mounted
	# $18 - Number of Write Errors
	# $19 - Number of Read Errors

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c02=(`cat ${TSM_STATS} | awk -F '\t' '{print $2}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c08=(`cat ${TSM_STATS} | awk -F '\t' '{print $8}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c11=(`cat ${TSM_STATS} | awk -F '\t' '{print $11}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c13=(`cat ${TSM_STATS} | awk -F '\t' '{print $13}'| tr -d ' ' | tr -d ',' | sed 's/^$/n\/a/g'`)
	array_c18=(`cat ${TSM_STATS} | awk -F '\t' '{print $18}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c19=(`cat ${TSM_STATS} | awk -F '\t' '{print $19}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		printf '{'
		printf "\"vol_name\":\"${array_c01[$i]}\","
		printf "\"vol_stgpool\":\"${array_c02[$i]}\","
		printf "\"vol_access\":\"${array_c08[$i]}\","
		printf "\"vol_err_state\":\"${array_c11[$i]}\","
		printf "\"vol_mounts\":\"${array_c13[$i]}\","
		printf "\"vol_w_err\":\"${array_c18[$i]}\","
		printf "\"vol_r_err\":\"${array_c19[$i]}\"}"

		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function discover_libr {
	local TSM_STATS=${tmp_dir}/zbxtsm_libr_stats.txt
	local x
	tsm_cmd -displaymode=list q libr > $TSM_STATS
	# for reference:
	# $1 - field title 'Library Name'
	# $2 - field value of 'Library Name'

	discover_path
	discover_libvol

	length_cur=1
	printf  "["
	array_n=(`cat ${TSM_STATS} | grep -E 'Library Name' | awk -F':' '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_v=(`cat ${TSM_STATS} | grep -E 'Library Name' | awk -F':' '{print $2}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_n[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		libr=${array_v[$i]}
		libr_scratch_vol=`cat "$LIBV_STATS" | grep "$libr" | grep "Scratch" | wc -l | xargs`
		libr_data_vol=`cat "$LIBV_STATS" | grep "$libr" | grep "Data" | wc -l | xargs`
		libr_dbbackup_vol=`cat "$LIBV_STATS" | grep "$libr" | grep "DbBackup" | wc -l | xargs`
		libr_stat=`cat "$PATH_STATS" | grep "$internal_tsmserver_name" | grep "$libr" | awk '{print $NF}'`
		[[ $libr_stat == "Yes" ]] && libr_stat=Online || libr_stat=Offline
		printf '{'
		printf "\"lib_name\":\"${array_v[$i]}\","
		printf "\"lib_status\":\"${libr_stat}\","
		printf "\"lib_vol_scr\":\"${libr_scratch_vol}\","
		printf "\"lib_vol_dat\":\"${libr_data_vol}\","
		printf "\"lib_vol_bak\":\"${libr_dbbackup_vol}\"}"
		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function discover_drives {
	local TSM_STATS=${tmp_dir}/zbxtsm_drv_stats.txt
	local drv
	local x
	tsm_cmd -tab -displaymode=table q drive > $TSM_STATS
	# for reference:
	# $1 - Library Name
	# $2 - Drive Name
	# $3 - Device Type
	# $4 - On-Line

	discover_path

	length_cur=1
	printf  "["
	array_c1=(`cat ${TSM_STATS} | awk '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c2=(`cat ${TSM_STATS} | awk '{print $2}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c3=(`cat ${TSM_STATS} | awk '{print $3}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c4=(`cat ${TSM_STATS} | awk '{print $4}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c1[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		drv=${array_c2[$i]}
		drv_stat=${array_c4[$i]}
		path_stat=`cat "$PATH_STATS" | grep "$internal_tsmserver_name" | grep "$drv" | awk '{print $NF}'`
		[[ $drv_stat == "Yes" ]] && drv_stat=Online || drv_stat=Offline
		[[ $path_stat == "Yes" ]] && path_stat=Online || path_stat=Offline
		printf '{'
		printf "\"lib_name\":\"${array_c1[$i]}\","
		printf "\"drv_name\":\"${array_c2[$i]}\","
		printf "\"drv_type\":\"${array_c3[$i]}\","
		printf "\"drv_status\":\"${drv_stat}\","
		printf "\"drv_path\":\"${path_stat}\"}"
		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function discover_nodedata {
	local TSM_STATS=${tmp_dir}/zbxtsm_nodedata_discover.txt
	local x
	tsm_cmd -tab -displaymode=tab q nodeda "*" | awk -F '\t' '{print $3, $1}' | sort -u > $TSM_STATS
	# for reference:
	# $1 - Node Name
	# $3 - Storage Pool Name

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c02=(`cat ${TSM_STATS} | awk '{print $2}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		tsm_stgp=${array_c01[$i]}
		tsm_node=${array_c02[$i]}
		# sum precisely as floats
		node_data_mb=$(tsm_cmd -tab -displaymode=tab q nodeda "$tsm_node" stgp="$tsm_stgp" | awk -F '\t' '{print $4}' | tr -d "," | awk '{sum+=sprintf("%f",$1)}END{printf "%.2f",sum}')
		# sum integers only. comment out float calculation if you decide to use integer calculation.
		#node_data_mb=$(tsm_cmd -tab -displaymode=tab q nodeda "$tsm_node" stgp="$tsm_stgp" | awk -F '\t' '{print $4}' | tr -d "," | cut -d. -f1 | awk '{print $1}'|awk '{sum+=$1} END {print sum}')
		printf '{'
		printf "\"stgp_name\":\"${array_c01[$i]}\","
		printf "\"node_name\":\"${array_c02[$i]}\","
		printf "\"node_data_mb\":\"${node_data_mb}\"}"
		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function nodedata_cronjob {
	local TSM_STATS=${tmp_dir}/zbxtsm_nodedata_stats.txt
	local tmp_TSM_STATS=${tmp_dir}/zbxtsm_nodedata_stats.tmp
	local x

	[[ ! -f $TSM_STATS ]] && echo "[]" > $TSM_STATS	

	discover_nodedata > $tmp_TSM_STATS 2>/dev/null
	/bin/mv $tmp_TSM_STATS $TSM_STATS
	
}

function nodedata_get {
	local TSM_STATS=${tmp_dir}/zbxtsm_nodedata_stats.txt
	local x

	[[ ! -f $TSM_STATS ]] && echo "[]" || cat $TSM_STATS

}

function discover_stgp {
	local TSM_STATS=${tmp_dir}/zbxtsm_stgp_stats.txt
	local x
	tsm_cmd -tab q stgp f=d > $TSM_STATS
	# for reference:
	# $1 - Storage Pool Name
	# $2 - Storage Pool Type
	# $4 - Estimated Capacity
	# $6 - Pct Util
	# $18 - Access
	# $25 - Maximum Scratch Volumes Allowed
	# $26 - Number of Scratch Volumes Used

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c02=(`cat ${TSM_STATS} | awk -F '\t' '{print $2}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c04=(`cat ${TSM_STATS} | awk -F '\t' '{print $4}'| tr -d "," | cut -d " " -f1 | cut -d "." -f1 | tr -d " " | sed 's/^$/n\/a/g'`)
	arr_unit=(`cat ${TSM_STATS} | awk -F '\t' '{print $4}'| cut -d " " -f2 | sed 's/^$/B/g'`)
	array_c06=(`cat ${TSM_STATS} | awk -F '\t' '{print $6}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c18=(`cat ${TSM_STATS} | awk -F '\t' '{print $18}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c25=(`cat ${TSM_STATS} | awk -F '\t' '{print $25}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c26=(`cat ${TSM_STATS} | awk -F '\t' '{print $26}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		if [[ ${arr_unit[$i]} == "K" ]]; then
			m=1024
		elif [[ ${arr_unit[$i]} == "M" ]]; then
			m=1048576
		elif [[ ${arr_unit[$i]} == "G" ]]; then
			m=1073741824
		elif [[ ${arr_unit[$i]} == "T" ]]; then
			m=1099511627776
		else
			echo unit: ${arr_unit[$i]}
			m=1
		fi

		stgp_size_b=$((${array_c04[${i}]}*${m}))
		printf '{'
		printf "\"stgp_name\":\"${array_c01[$i]}\","
		printf "\"stgp_type\":\"${array_c02[$i]}\","
		printf "\"stgp_size_b\":\"${stgp_size_b}\","
		printf "\"stgp_util_pcnt\":\"${array_c06[$i]}\","
		printf "\"stgp_acc_mode\":\"${array_c18[$i]}\","
		printf "\"stgp_max_scr\":\"${array_c25[$i]}\","
		printf "\"stgp_used_scr\":\"${array_c26[$i]}\"}"

		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function discover_client_sched {
	local TSM_STATS=${tmp_dir}/zbxtsm_clisched_discovery.txt
	local x
	tsm_cmd -tab q sched f=d > $TSM_STATS
	# for reference:
	# $1 - Policy Domain Name
	# $2 - Schedule Name
	# $8 - Priority
	# $9 - Start Date/Time
	# $10 - Duration
	# $12 - Period
	# $13 - Day of Week
	# $14 - Month
	# $15 - Day of Month
	# $16 - Week of Month
	# $17 - Expiration
	# $19 - Last Update Date/Time

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}' | tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c02=(`cat ${TSM_STATS} | awk -F '\t' '{print $2}' | tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c08=(`cat ${TSM_STATS} | awk -F '\t' '{print $8}' | tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c09=(`cat ${TSM_STATS} | awk -F '\t' '{print $9}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c10=(`cat ${TSM_STATS} | awk -F '\t' '{print $10}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c12=(`cat ${TSM_STATS} | awk -F '\t' '{print $12}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c13=(`cat ${TSM_STATS} | awk -F '\t' '{print $13}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c14=(`cat ${TSM_STATS} | awk -F '\t' '{print $14}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c15=(`cat ${TSM_STATS} | awk -F '\t' '{print $15}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c16=(`cat ${TSM_STATS} | awk -F '\t' '{print $16}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c17=(`cat ${TSM_STATS} | awk -F '\t' '{print $17}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c19=(`cat ${TSM_STATS} | awk -F '\t' '{print $19}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		sched_dom="${array_c01[$i]}"
		sched_name="${array_c02[$i]}"
		q_sched_dom=\'${sched_dom}\'
		q_sched_name=\'${sched_name}\'
		sched_prior="${array_c08[$i]}"
		sched_window="${array_c10[$i]}"
		# convert schedule window to hours (minimum: 1h; maximum: 168h)
		if [[ `echo "$sched_window" | grep -i "indefinite"` ]]; then
			sched_window_h=168
		elif [[ `echo "$sched_window" | grep -i "day"` ]]; then
			days=`echo "$sched_window" | awk -F '_' '{print $1}'`
			[[ $days == +([0-9]) ]] || days=1
			sched_window_h=$(($days * 24))
			[[ $sched_window_h -gt 168 ]] && sched_window_h=168
		elif [[ `echo "$sched_window" | grep -i "hour"` ]]; then
			hours=`echo "$sched_window" | awk -F '_' '{print $1}'`
			[[ $hours == +([0-9]) ]] || hours=1
			sched_window_h=$hours
		else
			sched_window_h=1
		fi
		sched_start_dt="Start: ${array_c09[$i]};"
		sched_start_period="Period: ${array_c12[$i]};"
		sched_start_wd="WeekDay: ${array_c13[$i]};"
		sched_start_m="Month: ${array_c14[$i]};"
		sched_start_dm="MonthDay: ${array_c15[$i]};"
		sched_start_wm="WeekOfMonth: ${array_c16[$i]};"
		[[ ${array_c17[$i]} == "n/a" ]] && sched_expire="${array_c17[$i]}" || sched_expire=$(tsm_cmd -tab "SELECT expiration from client_schedules WHERE DOMAIN_NAME=${q_sched_dom} AND SCHEDULE_NAME=${q_sched_name}")
		sched_start="$sched_start_dt $sched_start_period $sched_start_wd $sched_start_m $sched_start_dm $sched_start_wm"
		sched_last_changed="${array_c19[$i]}"
		# get number of associated clients
		sched_num_assoc=$(tsm_cmd -tab "SELECT count(*) FROM associations WHERE domain_name=${q_sched_dom} AND schedule_name=${q_sched_name}" 2>/dev/null | xargs | grep -Ev "ANR2034E|ANS8001I")
		[[ -z "$sched_num_assoc" ]] && sched_num_assoc=0
		# get number of completed/missed/failed tasks for previous day
		if [[ $sched_num_assoc -gt 0 ]]; then
			sched_done_y=$(tsm_cmd -tab "q ev ${q_sched_dom} ${q_sched_name} begindate=today-1 enddate=today-1" | grep -i 'Completed' | wc -l | xargs)
			sched_miss_y=$(tsm_cmd -tab "q ev ${q_sched_dom} ${q_sched_name} begindate=today-1 enddate=today-1" | grep -i 'Missed' | wc -l | xargs)
			sched_fail_y=$(tsm_cmd -tab "q ev ${q_sched_dom} ${q_sched_name} begindate=today-1 enddate=today-1" | grep -i 'Failed' | wc -l | xargs)
		else
			sched_done_y=0
			sched_miss_y=0
			sched_fail_y=0
		fi

		printf '{'
		printf "\"sched_dom\":\"${sched_dom}\","
		printf "\"sched_name\":\"${sched_name}\","
		printf "\"sched_prior\":\"${sched_prior}\","
		printf "\"sched_window\":\"${sched_window}\","
		printf "\"sched_window_hours\":\"${sched_window_h}\","
		printf "\"sched_start\":\"${sched_start}\","
		printf "\"sched_expire\":\"${sched_expire}\","
		printf "\"sched_last_changed\":\"${sched_last_changed}\","
		printf "\"sched_num_assoc\":\"${sched_num_assoc}\","
		printf "\"sched_done_y\":\"${sched_done_y}\","
		printf "\"sched_miss_y\":\"${sched_miss_y}\","
		printf "\"sched_fail_y\":\"${sched_fail_y}\"}"

		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function clisched_cronjob {
	local TSM_STATS=${tmp_dir}/zbxtsm_clisched_stats.txt
	local tmp_TSM_STATS=${tmp_dir}/zbxtsm_clisched_stats.tmp
	local x

	[[ ! -f $TSM_STATS ]] && echo "[]" > $TSM_STATS

	discover_client_sched > $tmp_TSM_STATS 2>/dev/null
	/bin/mv $tmp_TSM_STATS $TSM_STATS

}

function clisched_get {
	local TSM_STATS=${tmp_dir}/zbxtsm_clisched_stats.txt
	local x

	[[ ! -f $TSM_STATS ]] && echo "[]" || cat $TSM_STATS

}

function get_failed_baksched {
	[[ $# -ne 3 ]] && echo "Provide arguments: dom_name sched_name sched_window_duration" && exit 1
	local dom_name=\'$1\'
	local sched_name=\'$2\'
	local sched_window_h=$3
	local epoch_now=`date +%s`
	local offset_s=$(($sched_window_h * 60 * 60))
	local epoch_past=$((${epoch_now} - ${offset_s}))

	local sql="SELECT count(*) FROM events WHERE domain_name=${dom_name} AND schedule_name=${sched_name} AND (status='Failed' OR status='Severed' OR status='Missed') AND ACTUAL_START>=(TIMESTAMP('1970-01-01-00.00.00.000000') + $epoch_past seconds) AND ACTUAL_START<=(TIMESTAMP('1970-01-01-00.00.00.000000') + $epoch_now seconds)"

	local sql2="SELECT DISTINCT NODE_NAME FROM events WHERE domain_name=${dom_name} AND schedule_name=${sched_name} AND (status='Failed' OR status='Severed' OR status='Missed') AND ACTUAL_START>=(TIMESTAMP('1970-01-01-00.00.00.000000') + $epoch_past seconds) AND ACTUAL_START<=(TIMESTAMP('1970-01-01-00.00.00.000000') + $epoch_now seconds)"

	#tsm_cmd -displaymode=list "$sql2"
	#exit

	# Run the select statements
	tsm_output="$(tsm_cmd -tab "$sql")"
	num_sched=$(echo "$tsm_output" | sed -n '/^[0-9][0-9]*$/p')
	[[ "$num_sched" -ne 0 ]] && tsm_output2="$(tsm_cmd -tab "$sql2" | xargs | tr ' ' ';')" && msg="$num_sched on nodes: $tsm_output2" || msg=""

	echo "$msg"
}

function discover_adm_sched {
	local TSM_STATS=${tmp_dir}/zbxtsm_admsched_discovery.txt
	local x
	tsm_cmd -tab q sched t=a f=d > $TSM_STATS
	# for reference:
	# $1 - Schedule Name
	# $4 - Priority
	# $5 - Start Date/Time
	# $6 - Duration
	# $8 - Period
	# $9 - Day of Week
	# $10 - Month
	# $11 - Day of Month
	# $12 - Week of Month
	# $13 - Expiration
	# $14 - Active
	# $16 - Last Update Date/Time

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}' | tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c04=(`cat ${TSM_STATS} | awk -F '\t' '{print $4}' | tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c05=(`cat ${TSM_STATS} | awk -F '\t' '{print $5}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c06=(`cat ${TSM_STATS} | awk -F '\t' '{print $6}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c08=(`cat ${TSM_STATS} | awk -F '\t' '{print $8}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c09=(`cat ${TSM_STATS} | awk -F '\t' '{print $9}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c10=(`cat ${TSM_STATS} | awk -F '\t' '{print $10}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c11=(`cat ${TSM_STATS} | awk -F '\t' '{print $11}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c12=(`cat ${TSM_STATS} | awk -F '\t' '{print $12}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c13=(`cat ${TSM_STATS} | awk -F '\t' '{print $13}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c14=(`cat ${TSM_STATS} | awk -F '\t' '{print $14}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c16=(`cat ${TSM_STATS} | awk -F '\t' '{print $16}' | tr ' ' '_' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		x=$(($i + 1))
		adm_sched_name="${array_c01[$i]}"
		q_adm_sched_name=\'${adm_sched_name}\'
		adm_sched_prior="${array_c04[$i]}"
		adm_sched_window="${array_c06[$i]}"
		# convert schedule window to hours (minimum: 1h; maximum: 168h)
		if [[ `echo "$adm_sched_window" | grep -i "indefinite"` ]]; then
			adm_sched_window_h=168
		elif [[ `echo "$adm_sched_window" | grep -i "day"` ]]; then
			days=`echo "$adm_sched_window" | awk -F '_' '{print $1}'`
			[[ $days == +([0-9]) ]] || days=1
			adm_sched_window_h=$(($days * 24))
			[[ $adm_sched_window_h -gt 168 ]] && adm_sched_window_h=168
		elif [[ `echo "$adm_sched_window" | grep -i "hour"` ]]; then
			hours=`echo "$adm_sched_window" | awk -F '_' '{print $1}'`
			[[ $hours == +([0-9]) ]] || hours=1
			adm_sched_window_h=$hours
		else
			adm_sched_window_h=1
		fi
		adm_sched_start_dt="Start: ${array_c05[$i]};"
		adm_sched_start_period="Period: ${array_c08[$i]};"
		adm_sched_start_wd="WeekDay: ${array_c09[$i]};"
		adm_sched_start_m="Month: ${array_c10[$i]};"
		adm_sched_start_dm="MonthDay: ${array_c11[$i]};"
		adm_sched_start_wm="WeekOfMonth: ${array_c12[$i]};"
		[[ ${array_c13[$i]} == "n/a" ]] && adm_sched_expire="${array_c13[$i]}" || adm_sched_expire=$(tsm_cmd -tab "SELECT EXPIRATION from admin_schedules WHERE SCHEDULE_NAME=${q_adm_sched_name}")
		adm_sched_start="$adm_sched_start_dt $adm_sched_start_period $adm_sched_start_wd $adm_sched_start_m $adm_sched_start_dm $adm_sched_start_wm"
		adm_sched_active="${array_c14[$i]}"
		adm_sched_last_changed="${array_c16[$i]}"
		# get number of completed/missed/failed tasks for previous day
		if [[ "$adm_sched_active" == "Yes" ]]; then
			adm_sched_done_y=$(tsm_cmd -tab "q ev ${q_adm_sched_name} t=a begindate=today-1 enddate=today-1" | grep -i 'Completed' | wc -l | xargs)
			adm_sched_miss_y=$(tsm_cmd -tab "q ev ${q_adm_sched_name} t=a begindate=today-1 enddate=today-1" | grep -i 'Missed' | wc -l | xargs)
			adm_sched_fail_y=$(tsm_cmd -tab "q ev ${q_adm_sched_name} t=a begindate=today-1 enddate=today-1" | grep -i 'Failed' | wc -l | xargs)
		else
			adm_sched_done_y=0
			adm_sched_miss_y=0
			adm_sched_fail_y=0
		fi

		printf '{'
		printf "\"adm_sched_name\":\"${adm_sched_name}\","
		printf "\"adm_sched_prior\":\"${adm_sched_prior}\","
		printf "\"adm_sched_window\":\"${adm_sched_window}\","
		printf "\"adm_sched_window_hours\":\"${adm_sched_window_h}\","
		printf "\"adm_sched_start\":\"${adm_sched_start}\","
		printf "\"adm_sched_expire\":\"${adm_sched_expire}\","
		printf "\"adm_sched_last_changed\":\"${adm_sched_last_changed}\","
		printf "\"adm_sched_active\":\"${adm_sched_active}\","
		printf "\"adm_sched_done_y\":\"${adm_sched_done_y}\","
		printf "\"adm_sched_miss_y\":\"${adm_sched_miss_y}\","
		printf "\"adm_sched_fail_y\":\"${adm_sched_fail_y}\"}"

		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function get_failed_admsched {
	[[ $# -ne 2 ]] && echo "Provide arguments: adm_sched_name adm_sched_window_h" && exit 1
	local adm_sched_name=\'$1\'
	local adm_sched_window_h=$2
	local epoch_now=`date +%s`
	local offset_s=$(($adm_sched_window_h * 60 * 60))
	local epoch_past=$((${epoch_now} - ${offset_s}))

	local sql="SELECT count(*) FROM events WHERE schedule_name=${adm_sched_name} AND (status='Failed' OR status='Severed' OR status=' Missed') AND ACTUAL_START>=(TIMESTAMP('1970-01-01-00.00.00.000000') + $epoch_past seconds) AND ACTUAL_START<=(TIMESTAMP('1970-01-01-00.00.00.000000') + $epoch_now seconds)"

	# Run the select statements
	tsm_output="$(tsm_cmd -tab "$sql")"
	num_sched=$(echo "$tsm_output" | sed -n '/^[0-9][0-9]*$/p')
	
	echo "$num_sched"
}

function discover_dbbak_vol {
	local TSM_STATS=${tmp_dir}/zbxtsm_dbbakvol_stats.txt
	local x
	for lv in $(tsm_cmd -tab q libv | grep -i "DbBackup" | awk -v OFS=';' -F '\t' '{print $1, $2}'); do
		libr=`echo "$lv" | awk -F ';' '{print $1}'`
		voln=\'`echo "$lv" | awk -F ';' '{print $2}'`\'
		sql_p1="((days(timestamp(DATE_TIME)) - days(timestamp('1970-01-01'))) * 86400  + midnight_seconds(timestamp(DATE_TIME))) as epoch_time"
		sql_p2="SELECT DATE_TIME,VOLUME_NAME,TYPE,${sql_p1} FROM volhistory WHERE DATE_TIME=(SELECT MAX(DATE_TIME)"
		sql_p3="${sql_p2} FROM volhistory WHERE VOLUME_NAME=${voln} AND TYPE like '%BACKUP%')"
		sql="$sql_p3"
		
		sql_result=$(tsm_cmd -tab "$sql" 2>/dev/null | grep -Ev 'ANR2034E|ANS8001I')
		[[ ! -z "$sql_result" ]] &&  echo -e "$sql_result\t$libr"
	done > $TSM_STATS
	# for reference:
	# $1 - DATE_TIME (from volhistory)
	# $2 - Volume Name (from volhistory)
	# $3 - TYPE (from volhistory)
	# $4 - EPOCH_TIME (converted from DATE_TIME)
	# $5 - Library Name (from 'q libr')

	last_backup_time=$(cat ${TSM_STATS} | awk -F '\t' '{print $4}' | tr -d ' ' | sed 's/^$/n\/a/g'|grep -v 'n/a' | sort -n | tail -1)

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c02=(`cat ${TSM_STATS} | awk -F '\t' '{print $2}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c03=(`cat ${TSM_STATS} | awk -F '\t' '{print $3}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c04=(`cat ${TSM_STATS} | awk -F '\t' '{print $4}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c05=(`cat ${TSM_STATS} | awk -F '\t' '{print $5}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		printf '{'
		printf "\"dbbak_last\":\"${last_backup_time}\","
		printf "\"dbbak_vol\":\"${array_c02[$i]}\","
		printf "\"dbbak_type\":\"${array_c03[$i]}\","
		printf "\"dbbak_date\":\"${array_c04[$i]}\","
		printf "\"dbbak_library\":\"${array_c05[$i]}\"}"

		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function discover_policy {
	local TSM_STATS=${tmp_dir}/zbxtsm_policy_stats.txt
	local x
	tsm_cmd -tab q pol f=d > $TSM_STATS
	# for reference:
	# $1 - Policy Domain Name
	# $2 - Policy Set Name
	# $3 - Default Mgmt Class Name
	# $6 - Last Update Date/Time
	# $8 - Changes Pending

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}'| tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c02=(`cat ${TSM_STATS} | awk -F '\t' '{print $2}'| tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c03=(`cat ${TSM_STATS} | awk -F '\t' '{print $3}'| tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c06=(`cat ${TSM_STATS} | awk -F '\t' '{print $6}'| tr ' ' '_' | sed 's/^$/n\/a/g'`)
	array_c08=(`cat ${TSM_STATS} | awk -F '\t' '{print $8}'| tr ' ' '_' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		printf '{'
		printf "\"pol_dom_name\":\"${array_c01[$i]}\","
		printf "\"pol_set_name\":\"${array_c02[$i]}\","
		printf "\"pol_mgmt_class\":\"${array_c03[$i]}\","
		printf "\"pol_last_changed\":\"${array_c06[$i]}\","
		printf "\"pol_chnange_pending\":\"${array_c08[$i]}\"}"

		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function node_last_ba {
	local q_node_name=\'$1\'
	local q_node_pdom=\'$2\'

	sql_p1="((days(timestamp(ACTUAL_START)) - days(timestamp('1970-01-01'))) * 86400  + midnight_seconds(timestamp(ACTUAL_START))) as epoch_time"
	sql_p2="SELECT DISTINCT $sql_p1, status FROM events WHERE ACTUAL_START=(SELECT max(ACTUAL_START) FROM events"
	sql_p3="WHERE DOMAIN_NAME=${q_node_pdom} AND NODE_NAME=${q_node_name})"
	sql="$sql_p2 $sql_p3"
	sql_result=$(tsm_cmd -displaymode=list "$sql" 2>/dev/null | grep -Ev 'ANR2034E|ANS8001I')
	last_ba_date=$(echo "$sql_result" | grep -i "epoch_time" | awk -F':' '{print $2}' | xargs)
	last_ba_status=$(echo "$sql_result" | grep -i "STATUS" | awk -F':' '{print $2}' | xargs)
	[[ -z "$last_ba_date" ]] && last_ba_date=0
	[[ -z "$last_ba_status" ]] && last_ba_status="NA"

	echo "$last_ba_date;$last_ba_status"
}

function discover_nodes {
	local TSM_STATS=${tmp_dir}/zbxtsm_nodes_discovery.txt
	NODE_STATS=$TSM_STATS
	local x
	tsm_cmd -tab q node f=d > $TSM_STATS
	# for reference:
	# $1 - Node Name
	# $5 - Policy Domain Name
	# $7 - Days Since Last Access
	# $10 - Invalid Sign-on Count

	length_cur=1
	printf  "["
	array_c01=(`cat ${TSM_STATS} | awk -F '\t' '{print $1}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c05=(`cat ${TSM_STATS} | awk -F '\t' '{print $5}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	array_c07=(`cat ${TSM_STATS} | awk -F '\t' '{print $7}'| tr -d ' ,' | sed 's/^$/n\/a/g'`)
	array_c10=(`cat ${TSM_STATS} | awk -F '\t' '{print $10}'| tr -d ' ' | sed 's/^$/n\/a/g'`)
	length_arr=${#array_c01[@]}

	for ((i=0;i<$length_arr;i++))
	do
		node_name="${array_c01[$i]}"
		node_pdom="${array_c05[$i]}"
		[[ `echo "${array_c07[$i]}" | grep '<'` ]] && node_days_laccess=0 || node_days_laccess="${array_c07[$i]}"
		nodes_assoc_num=$(tsm_cmd -tab q assoc | grep "$node_name" | wc -l | xargs)
		node_lba=$(node_last_ba "$node_name" "$node_pdom")
		node_lba_date=$(echo "$node_lba" | awk -F';' '{print $1}')
		node_lba_status=$(echo "$node_lba" | awk -F';' '{print $2}')
		printf '{'
		printf "\"node_name\":\"${array_c01[$i]}\","
		printf "\"node_pdom\":\"${array_c05[$i]}\","
		printf "\"node_days_laccess\":\"${node_days_laccess}\","
		printf "\"node_flogins\":\"${array_c10[$i]}\","
		printf "\"nodes_assoc_num\":\"${nodes_assoc_num}\","
		printf "\"node_lba_status\":\"${node_lba_status}\","
		printf "\"node_lba_date\":\"${node_lba_date}\"}"


		if [ $length_cur -lt $[length_arr] ];then
			printf ','
		fi
		let "length_cur = $length_cur +1"
	done
	printf  "]"
}

function nodes_cronjob {
	local TSM_STATS=${tmp_dir}/zbxtsm_nodes_stats.txt
	local tmp_TSM_STATS=${tmp_dir}/zbxtsm_nodes_stats.tmp
	local x

	[[ ! -f $TSM_STATS ]] && echo "[]" > $TSM_STATS

	discover_nodes > $tmp_TSM_STATS 2>/dev/null
	/bin/mv $tmp_TSM_STATS $TSM_STATS

}

function nodes_get {
	local TSM_STATS=${tmp_dir}/zbxtsm_nodes_stats.txt
	local x

	[[ ! -f $TSM_STATS ]] && echo "[]" || cat $TSM_STATS

}

function db_usage {
	local sql="SELECT CAST(SUM(100-(free_space_mb*100) / tot_file_system_mb) AS DECIMAL(3,1)) AS PCT_UTILIZED FROM db"
	tsm_cmd -tab "$sql" 2>/dev/null | xargs
}

function tsm_uptime {
	tsm_cmd "SELECT RESTART_DATE FROM status" 2>/dev/null | xargs
}

## MAIN ##
	case "$1" in
		# shift is used for passing arguments to functions if applicable
		discover_libr )
			func="$1"
			shift
			$func "$@"
		;;
		discover_drives )
			func="$1"
			shift
			$func "$@"
		;;
		discover_vol )
			func="$1"
			shift
			$func "$@"
		;;
		discover_nodedata )
			func="$1"
			shift
			$func "$@"
		;;
		nodedata_cronjob )
			func="$1"
			shift
			$func "$@"
		;;
		nodedata_get )
			func="$1"
			shift
			$func "$@"
		;;
		discover_stgp )
			func="$1"
			shift
			$func "$@"
		;;
		discover_client_sched )
			func="$1"
			shift
			$func "$@"
		;;
		get_failed_baksched )
			func="$1"
			shift
			$func "$@"
		;;
		clisched_cronjob )
			func="$1"
			shift
			$func "$@"
		;;
		clisched_get )
			func="$1"
			shift
			$func "$@"
		;;
		discover_adm_sched )
			func="$1"
			shift
			$func "$@"
		;;
		get_failed_admsched )
			func="$1"
			shift
			$func "$@"
		;;
		discover_dbbak_vol )
			func="$1"
			shift
			$func "$@"
		;;
		discover_policy )
			func="$1"
			shift
			$func "$@"
		;;
		discover_nodes )
			func="$1"
			shift
			$func "$@"
		;;
		nodes_cronjob )
			func="$1"
			shift
			$func "$@"
		;;
		nodes_get )
			func="$1"
			shift
			$func "$@"
		;;
		tsm_uptime )
			func="$1"
			shift
			$func "$@"
		;;
		db_usage )
			func="$1"
			shift
			$func "$0"
		;;
		* )
			echo "function '$1' not found"
		;;
	esac
