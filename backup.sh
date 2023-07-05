#!/bin/bash
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

ENCRYPT_KEY=""
BACKUP_NAME=""
B2_BUCKET_NAME=""
BANDWIDTH_LIMIT="2M"

# http://duplicity.nongnu.org/vers8/duplicity.1.html

day=$(date '+%d')
month=$(date '+%m')

# every 3 months, delete the oldest full backup and make a new one
if [ $day == 01 ] && ( [ $month == 01 ] || [ $month == 04 ] || [ $month == 07 ] || [ $month == 10 ] ); then
	echo "time for a FULL backup"
	echo "purging old backups"
	nice duplicity remove-all-but-n-full 2 --force --encrypt-key $ENCRYPT_KEY --name $BACKUP_NAME file:///backups/duplicity

	echo "starting duplicity full backup"
	nice duplicity full --encrypt-key $ENCRYPT_KEY --name $BACKUP_NAME --exclude-filelist=/etc/duplicity/backup-excludes / file:///backups/duplicity

else
	# i don't think we need to worry about purging incrementals
	echo "starting duplicity incremental backup"
	nice duplicity incremental --encrypt-key $ENCRYPT_KEY --name $BACKUP_NAME --exclude-filelist=/etc/duplicity/backup-excludes / file:///backups/duplicity
fi

echo "starting rclone backup sync to cloud"
rclone --bwlimit $BANDWIDTH_LIMIT sync /backups/duplicity/ b2:$B2_BUCKET_NAME/

echo "backup complete"
