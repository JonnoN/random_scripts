#!/bin/bash
set -e
exec 1> >(logger -s -t $(basename $0)) 2>&1

echo "MySQL backup starting"
mysqldump --single-transaction --all-databases --routines | gzip > /backups/mysql/`date +%Y-%m-%d_%H:%M:%S`.sql.gz
echo "MySQL backup complete"
find /backups/mysql/* -mtime +8 -exec rm '{}' \;

