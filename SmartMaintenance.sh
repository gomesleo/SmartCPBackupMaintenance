#!/bin/bash

##################################################################################
##			SMART CPANEL BACKUP MAINTENANCE				##
##################################################################################
##										##
##	 AUTOR'S NAME:	Leonardo Gomes						##
##	CREATION DATE:	Dec, 15 2017						##
##	      VERSION:	1.0							##
##										##
##	 CONTACT INFO:	leonardo@hostbrasil.net					##
##		 SITE:	www.hostbrasil.net					##
##										##
##	       GITHUB:	https://github.com/gomesleo/SmartCPBackupMaintenance	##
##										##
##################################################################################
##										##
##	This program is free software: you can redistribute it and/or modify	##
##	it under the terms of the GNU General Public License as published by	##
##	the Free Software Foundation, either version 3 of the License, or	##
##	(at your option) any later version.					##
##										##
##	This program is distributed in the hope that it will be useful,		##
##	but WITHOUT ANY WARRANTY; without even the implied warranty of		##
##	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the		##
##	GNU General Public License for more details.				##
##										##
##	You should have received a copy of the GNU General Public License	##
##	along with this program.  If not, see <http://www.gnu.org/licenses/>.	##
##										##
##					## ABOUT THE SCRIPT ##			##
##										##
##			This script was developed to improve the maintenance	##
##			backup jobs into a cPanel/WHM Server, that's due the	##
##			unappropriate use of the quota resource, the backups	##
##			routines usually fail or takes long time to complete	##
##										##
##			This will enable/disable backup for accounts that is	##
##			over quota defined for included backups for each new	##
##			account.						##
##										##
##################################################################################
##										##
##		USE AT YOUR OWN RISK	----	WITHOUT ANY WARRANTY		##
##										##
##################################################################################

### GENERAL CONFIGURATION ###
basedir='/root/SmartCPBackupMaintenance/' # Full path of the script location with / at the end
xml='accounts.xml' # XML file extracted through whmapii
limit='1024' # Limit in MB
softlimit='95' # Value in % to notify user that it's near to get backup disabled due limit
skip='premium_skip' # List of premium accounts that has no limit for backups
limitpremium='5096' # Limit for backups in premium accounts in MB

### FILES CONFIGURATION ###
tpl_disabled='tpl_disabled.html' # Template for e-mails sent to disabled backup accounts
tpl_stilldisabled='tpl_stilldisabled.html' # Template for e-mails sent to inform users that backups still disabled
tpl_enabled='tpl_enabled.html' # Template for e-mails sent to re-enabled backup accounts
tpl_premiumenabled='tpl_premiumenabled.html' # Template for e-mails sent to re-enabled backup accounts
tpl_limitalert='tpl_limitalert.html' # Template for alert e-mails sent to accounts near the limit

### SUBJECT E-MAIL CONFIGURATION ###
subject_disabled='AVISO: BACKUP DE CONTA DESABILITADO' # E-mail subject fot disabled backup
subject_stilldisabled='ALERTA: BACKUP DE CONTA CONTINUA DESABILITADO' # E-mail subject for still disabled backup
subject_enabled='AVISO: BACKUP DE CONTA HABILITADO' # E-mail subject for enabled backup
subject_premiumenabled='AVISO: BACKUP PREMIUM HABILITADO' # E-mail subject for enabled backup
subject_limitalert='ATENÇÃO: CONTA PRÓXIMO AO LIMITE PARA BACKUP' # E-mail subject for alert of near limit
from_name='HB Server Administrator' # Display name of the sender
from_email='admin@hbserver.net' # E-mail of the sender

### SERVER  E-MAIL CONFIGURATION ###
smtp_addr='localhost'
smtp_port='25'
smtp_user=''
smtp_pass=''


### DO NOT CHANGE ANYTHING FROM HERE ###

xml=$basedir$xml
skip=$basedir$skip
tpl_disabled=$basedir$tpl_disabled
tpl_stilldisabled=$basedir$tpl_stilldisabled
tpl_enabled=$basedir$tpl_enabled
tpl_premiumenabled=$basedir$tpl_premiumenabled
tpl_limitalert=$basedir$tpl_limitalert
limitalert=$((limit*$softlimit/100))
user=($(grep -oP '(?<=user>)[^<]+' "$xml"))
diskused=($(grep -oP '(?<=diskused>)[^<]+' "$xml"))
backup=($(grep -oP '(?<=backup>)[^<]+' "$xml"))
email=($(grep -oP '(?<=email>)[^<]+' "$xml"))
domain=($(grep -oP '(?<=domain>)[^<]+' "$xml"))

smtp_send(){
 echo -e "\n[+] $smtp_addr:$smtp_port => $smtp_user:$smtp_pass"
 echo -e "[*] To: $1 | Message size: ${#3}"
 echo -e "[*] Subject: $2\n"
 echo -e "Sending ..."
 exec 5<>/dev/tcp/$smtp_addr/$smtp_port
 echo -e "EHLO $smtp_addr" >&5
 echo "auth login" >&5
 echo -n "$smtp_user" | base64 >&5
 echo -n "$smtp_pass" | base64 >&5
 echo "MAIL FROM: $smtp_user" >&5
 echo "RCPT TO: $1" >&5
 echo 'data' >&5
 echo "From: $from_name<$from_email>" >&5
 echo "Content-Type: text/html" >&5
 echo "To:<$1>" >&5
 echo -e "Subject: $2\n" >&5
 echo -e "$3\n.\nQUIT" >&5
 cat <&5
}

# Generate XML file with all accounts
echo "Generating XML File with all accounts..."
whmapi1 listaccts want=user,diskused,email,domain,backup --output=xml > $xml

for i in ${!user[*]}; do

	uso=`echo ${diskused[$i]} | awk -F'M' '{print $1}'`

	# Check if it's a premium account and don't change anything
	if [ `cat $skip | grep -x ${user[$i]}` ]; then

		# Check if user is disabled and enable as premium/skipped user
		if [ ${backup[$i]} -eq 0 ]; then

			# Re-enable backup and notify premium user if e-mail is set
                        echo "Enabling premium backup for user: ${user[$i]}"
                        whmapi1 modifyacct user=${user[$i]} backup=1

			emaildata=`cat $tpl_premiumenabled | sed "s/\[USER\]/${user[$i]}/g;s/\[DOMAIN\]/${domain[$i]}/g;s/\[LIMIT\]/$limit/g;s/\[LIMITPREMIUM\]/$limit/g;s/\[USED\]/$uso/g"`

			if [ ${email[$i]} != "*unknown*" ]; then

				# Send E-mail notifying user
				smtp_send "${email[$i]}" "$subject_premiumenabled" "$emaildata"

			fi

		fi
		

	else

		# Check if the account is using more than the limit set
		if [ $uso -gt $limit ]; then

			# Validate if the backup is active for the account over the limit
			if [ ${backup[$i]} -eq 1 ]; then
   
				# Disable backup and notify user if e-mail is set
                        	echo "Disabling backup for user: ${user[$i]}"
				whmapi1 modifyacct user=${user[$i]} backup=0

				emaildata=`cat $tpl_disabled | sed "s/\[USER\]/${user[$i]}/g;s/\[DOMAIN\]/${domain[$i]}/g;s/\[LIMIT\]/$limit/g;s/\[USED\]/$uso/g"`
				
				if [ ${email[$i]} != "*unknown*" ]; then

					# Send E-mail notifying user
					smtp_send "${email[$i]}" "$subject_disabled" "$emaildata"

				fi

			else

				# Notify user that the backup still disabled
				emaildata=`cat $tpl_stilldisabled | sed "s/\[USER\]/${user[$i]}/g;s/\[DOMAIN\]/${domain[$i]}/g;s/\[LIMIT\]/$limit/g;s/\[USED\]/$uso/g"`

                        	echo "Backup still disabled for user: ${user[$i]}"
				if [ ${email[$i]} != "*unknown*" ]; then

					# Send E-mail notifying user
					smtp_send "${email[$i]}" "$subject_stilldisabled" "$emaildata"

				fi

			fi
		else

			# Check if user is elegible for backup but is disabled
			if [ ${backup[$i]} -eq 0 ]; then

				# Re-enable backup and notify user if e-mail is set
                        	echo "Enabling backup for user: ${user[$i]}"
                                whmapi1 modifyacct user=${user[$i]} backup=1

				emaildata=`cat $tpl_enabled | sed "s/\[USER\]/${user[$i]}/g;s/\[DOMAIN\]/${domain[$i]}/g;s/\[LIMIT\]/$limit/g;s/\[USED\]/$uso/g"`

				if [ ${email[$i]} != "*unknown*" ]; then

					# Send E-mail notifying user
					smtp_send "${email[$i]}" "$subject_enabled" "$emaildata"

				fi

			fi

			# Check if account is near to reach the limit and notify user
			if [ $uso -gt $limitalert ]; then

                        	echo "Account exceeding limit for user: ${user[$i]}"

				# Notify user that account is near the limit and backup may be disabled
				emaildata=`cat $tpl_limitalert | sed "s/\[USER\]/${user[$i]}/g;s/\[DOMAIN\]/${domain[$i]}/g;s/\[LIMIT\]/$limit/g;s/\[USED\]/$uso/g"`

				if [ ${email[$i]} != "*unknown*" ]; then

					# Send E-mail notifying user
					smtp_send "${email[$i]}" "$subject_limitalert" "$emaildata"

				fi

			fi

		fi

	fi

done

