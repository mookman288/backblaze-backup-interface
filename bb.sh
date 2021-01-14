#!/bin/bash

if [ ! command -v b2 &> /dev/null ];
then
	echo "Please ensure that BackBlaze B2 CLI is installed."
	exit 1
fi

if [ ! command -v find &> /dev/null ];
then
	echo "Please ensure that find is installed."
	exit 1
fi

if [ ! command -v cat &> /dev/null ];
then
	echo "Please ensure that cat is installed."
	exit 1
fi

if [ ! command -v sed &> /dev/null ];
then
	echo "Please ensure that sed is installed."
	exit 1
fi

if [ ! command -v gzip &> /dev/null ];
then
	echo "Please ensure that gzip is installed."
	exit 1
fi

if [ ! command -v mail &> /dev/null ];
then
	echo "Please ensure that the mail command is installed."
	exit 1
fi

if [ ! command -v perl &> /dev/null ];
then
	echo "Please ensure that perl is installed."
	exit 1
fi

if [ ! command -v hostname &> /dev/null ];
then
	hostname=$(whoami)
else
	hostname=$(hostname)
fi

currentDate=$(date +"%d-%m-%Y")

if [ ! command -v mktemp &> /dev/null ];
then
	tmpDir="/tmp/bb.sh"
else
	tmpDir=$(mktemp -d)
fi

if [ ! -d "${tmpDir}" ];
then
	mkdir ${tmpDir}
fi

#https://www.ostricher.com/2014/10/the-right-way-to-get-the-directory-of-a-bash-script/
$PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Delete older files.
find "${PWD}/bbsh*" -maxdepth 0 -mtime +3 -delete -regex ".*\.log"
find "${PWD}/bbsh*" -maxdepth 0 -mtime +3 -delete -regex ".*\.tmp"
find "${PWD}/bbsh*" -maxdepth 0 -mtime +3 -delete -regex ".*\.txt"

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

logBackupBucketName="${bucketName}//\//-"
logBackup="${PWD}/bbsh-${currentDate}-${logBackupBucketName}-backup.log"
logBackupAlt="${PWD}/bbsh-${currentDate}-${logBackupBucketName}-backup-alt.log"

if [ -f "${logBackup}" ];
then
	rm "${logBackup}"
fi

if [ -f "${logBackupAlt}" ];
then
	rm "${logBackupAlt}"
fi

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
		# Remove the database if it exists.
		if [ -f ${tmpDir}/${database}.tar.gz ];
		then
			rm ${tmpDir}/${database}.tar.gz
		fi

		# Dump the database.
		mysqldump --skip-lock-tables --add-drop-table --allow-keywords -u $mysqlUsername -p$mysqlPassword ${database} | gzip > "${tmpDir}/${database}.tar.gz"

		# Backup the database to Backblaze.
		b2 upload-file $bucketName "${tmpDir}/${database}.tar.gz" "${database}.tar.gz" 2>>${logBackupAlt} 1>>${logBackup}
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
		b2 sync --excludeAllSymlinks $syncPath "b2://$bucketName" >${logBackup} 2>&1
	else
		b2 sync --excludeAllSymlinks --excludeRegex $5 $syncPath "b2://$bucketName" >${logBackup} 2>&1
	fi
fi

tmpEmail="${PWD}/bbsh-${currentDate}-${bucketName}-email.tmp"

if [ -f "${tmpEmail}" ];
then
	rm "${tmpEmail}"
fi

if [ -f "${logBackup}" ];
then
	if [ "$backupType" == "filesystem" ];
	then
		oldIFS=IFS
		IFS=';;'

		# Use regex to parse the backblaze log to gather information.
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
			# Remove non-printable characters.
			tr -cd "[:print:]" < ${logBackupAlt} > "${tmpEmail}"

			# Remove vertical bars.
			perl -i -p -e "s/\|/ /g" "${tmpEmail}"

			# Remove spaces.
			perl -i -p -e "s/ +/ /g" "${tmpEmail}"

			# Add new lines.
			perl -i -p -e "s/\]/\n/g" "${tmpEmail}"

			echo "" >> "${tmpEmail}"
		fi

		cat ${logBackup} >> "${tmpEmail}"
	fi
fi

if [ -f "${tmpEmail}" ];
then
	cat "${tmpEmail}" | mail -s "[${hostname}] B2 Backup Report (${backupType} - ${bucketName})" "${emailAddress}"

	cat "${tmpEmail}"
fi