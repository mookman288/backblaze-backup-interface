#!/bin/bash

if [ ! hash b2 2>/dev/null ];
then
	echo "Please ensure that BackBlaze B2 CLI is installed."
	exit 1
fi

if [ ! find b2 2>/dev/null ];
then
	echo "Please ensure that find is installed."
	exit 1
fi

if [ ! hash cat 2>/dev/null ];
then
	echo "Please ensure that cat is installed."
	exit 1
fi

if [ ! hash sed 2>/dev/null ];
then
	echo "Please ensure that sed is installed."
	exit 1
fi

if [ ! hash gzip 2>/dev/null ];
then
	echo "Please ensure that gzip is installed."
	exit 1
fi

if [ ! hash mail 2>/dev/null ];
then
	echo "Please ensure that the mail command is installed."
	exit 1
fi

if [ ! hash perl 2>/dev/null ];
then
	echo "Please ensure that perl is installed."
	exit 1
fi

if [ ! hash hostname 2>/dev/null ];
then
	hostname=$(whoami)
else
	hostname=$(hostname)
fi

currentDate=$(date +"%d-%m-%Y")

if [ ! hash mktemp 2>/dev/null ];
then
	tmpDir="/tmp/bb.sh"
else
	tmpDir=$(mktemp -d)
fi

if [ ! -d "${tmpDir}" ];
then
	mkdir ${tmpDir}
fi

if [ -z "$PWD" ];
then
	$PWD="."
fi

# Delete older files.
find . -mindepth 1 -mtime +3 -delete -name "*.log"
find . -mindepth 1 -mtime +3 -delete -name "*.tmp"
find . -mindepth 1 -mtime +3 -delete -name "*.txt"

if [ -z "$1" ];
then
	read -s "Please provide the email address for notification: " emailAddress

	if [ -z "$emailAddress" ];
	then
		echo "You must include an email address for notification."
		exit 1
	fi
else
	emailAddress=$1
fi

if [ -z "$2" ];
then
	read -s "What type of backup is this? [mysql / filesystem] " backupType

	if [ -z "$backupType" ];
	then
		echo "You must include a type of backup. Please try again."
		exit 1
	fi
else
	backupType=$2
fi

if [ -z "$3" ];
then
	read -s "Please provide the B2 bucket name for storage: " bucketName

	if [ -z "$bucketName" ];
	then
		echo "You must include a valid bucket name. Please try again."
		exit 1
	fi
else
	bucketName=$3
fi

echo "Cancelling all unfinished large files..."

b2 cancel_all_unfinished_large_files $bucketName

logBackup="${PWD}/${currentDate}-${bucketName}-backup.log"
logBackupAlt="${PWD}/${currentDate}-${bucketName}-backup-alt.log"

if [ "$backupType" == "mysql" ];
then
	if [ -z "$4" ];
	then
		read -s "Please provide the MySQL username as the first argument: " mysqlUsername
	else
		mysqlUsername=$4
	fi

	if [ -z "$5" ];
	then
		read -s -p "Please provide the MySQL password: " mysqlPassword
	else
		mysqlPassword=$5
	fi

	if ! mysql -u $mysqlUsername -p$mysqlPassword -e exit;
	then
		echo "Please enter valid credentials to access all database information."
		exit 1
	fi

	for database in `echo 'SHOW DATABASES' | mysql -u $mysqlUsername -p$mysqlPassword | sed /^Database$/d`
	do
		#Remove the database if it exists.
		if [ -f ${tmpDir}/${database}.tar.gz ];
		then
			rm ${tmpDir}/${database}.tar.gz
		fi

		#Dump the database.
		mysqldump --skip-lock-tables --add-drop-table --allow-keywords -u $mysqlUsername -p$mysqlPassword ${database} | gzip > "${tmpDir}/${database}.tar.gz"

		#Backup the database to Backblaze.
		b2 upload-file $bucketName "${tmpDir}/${database}.tar.gz" "${database}.tar.gz" >> ${logBackup} 2>>${logBackupAlt}
	done
else
	if [ -z "$4" ];
	then
			read -s "Please provide the folder path to sync: " syncPath
		if [ -z "$syncPath" ];
		then
			echo "You must provide the folder path to sync."
			exit 1
		fi
	else
			syncPath=$4
	fi

	if [ -z "$5" ];
	then
		b2 sync --excludeAllSymlinks $syncPath "b2://$bucketName" > ${logBackup} 2>&1
	else
		b2 sync --excludeAllSymlinks --excludeRegex $5 $syncPath "b2://$bucketName" > ${logBackup} 2>&1
	fi
fi

if [ -f "${logBackup}" ];
then
	tmpEmail="${PWD}/${currentDate}-${bucketName}-email.tmp"
	txtEmail="${PWD}/${currentDate}-${bucketName}-email.txt"

	if [ -f "${tmpEmail}" ];
	then
		rm "${tmpEmail}"
	fi

	if [ -f "${txtEmail}" ];
	then
		rm "${txtEmail}"
	fi

	if [ "$backupType" == "filesystem" ];
	then
		oldIFS=IFS
		IFS=';;'

		declare -a compare=( $(perl -ne 'while(m/(compare\:\s*[0-9]+\/[0-9]+\s*files)/g) { print "$1;;"; }' ${logBackup} ) )
		declare -a updated=( $(perl -ne 'while(m/(updated\:\s*[0-9]+\/[0-9]+\s*files)/g) { print "$1;;"; }' ${logBackup} ) )
		declare -a size=( $(perl -ne 'while(m/([0-9]{1,}\.{0,1}[0-9]{0,}\s*\/\s*[0-9]{1,}\.{0,1}[0-9]{0,}\s*[K|M|G|T][B])/g) { print "$1;;"; }' ${logBackup} ) )
		declare -a warnings=( $(perl -ne 'while(m/WARNING\:\s*(.*)[\n|\r|\t]/gm) { print "$1;;"; }' ${logBackup} ) )
		declare -a errors=( $(perl -ne 'while(m/ERROR\:\s*(.*)[\n|\r|\t]/gm) { print "$1;;"; }' ${logBackup} ) )
		declare -a services=( $(perl -ne 'while(m/ServiceError\:\s*(.*)[\n|\r|\t]/gm) { print "$1;;"; }' ${logBackup} ) )

		if [ ! -z "$errors" ];
		then
			for s in "${errors[@]}";
			do
				if [ ! -z "$s" ];
				then
					echo "Error: $s" >> "${tmpEmail}"
					echo "" >> "${tmpEmail}"
				fi
			done
		fi

		if [ ! -z "$services" ];
		then
			for s in "${services[@]}";
			do
				if [ ! -z "$s" ];
				then
					echo "Service Error: $s" >> "${tmpEmail}"
					echo "" >> "${tmpEmail}"
				fi
			done
		fi

		if [ ! -z "$warnings" ];
		then
			for s in "${warnings[@]}";
			do
				if [ ! -z "$s" ];
				then
					echo "Warning: $s" >> "${tmpEmail}"
					echo "" >> "${tmpEmail}"
				fi
			done
		fi

		if [ ! -f "/${currentDate}-email.tmp" ];
		then
			if [ ! -z "$compare" ];
			then
				string="${compare[-2]}"
				indices=( ${!compare[@]} )

				for ((i=${#indices[@]} - 1; i >= 0; i--));
				do
					if [ ! -z "${compare[indices[i]]}" ];
					then
						string="${compare[indices[i]]}"
						break
					fi
				done

				echo "Files to ${string}" >> "${tmpEmail}"
			fi

			if [ ! -z "$updated" ];
			then
				string="${updated[-2]}"
				indices=( ${!updated[@]} )

				for ((i=${#indices[@]} - 1; i >= 0; i--));
				do
					if [ ! -z "${updated[indices[i]]}" ];
					then
						string="${updated[indices[i]]}"
						break
					fi
				done

				echo "Files ${string}" >> "${tmpEmail}"
			fi

			if [ ! -z "$size" ];
			then
				string="${size[-2]}"
				indices=( ${!size[@]} )

				for ((i=${#indices[@]} - 1; i >= 0; i--));
				do
					if [ ! -z "${size[indices[i]]}" ];
					then
						string="${size[indices[i]]}"
						break
					fi
				done

				echo "Uploaded ${string}" >> "${tmpEmail}"
			fi
		fi



		IFS=oldIFS
	else
		if [ -f "${logBackupAlt}" ];
		then
			tr -cd "[:print:]\n" < ${logBackupAlt} > ${tmpEmail}

			echo "" >> ${tmpEmail}
		fi

		cat ${logBackup} > ${tmpEmail}
	fi


fi

if [ -f "${tmpEmail}" ];
then
	cat ${tmpEmail} > ${txtEmail}

	mail -s "[${hostname}] B2 Backup Report (${backupType})" $emailAddress < "${txtEmail}"

	echo "$(<${txtEmail})"
fi