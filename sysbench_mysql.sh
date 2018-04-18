#!/bin/bash
#set -x

# usage: $0 hostname
#
# script to run all of the (legacy) sysbench mysql tests with increasing thread counts.
# expects sysbench >= 1.0
# expects schema 'sbtest' to already be created.
# outputs to stdout, suggest piping to `tee sysbench_out.txt`
# TODO: adapt this script to use modern rather than legacy checks.
#

MYSQL_USER="sbtest"
MYSQL_PASSWORD=""

NUM_THREADS="4 16 32 64 128 192 256"
TABLE_SIZE="10000000"
RUN_TIME="300"
SYSBENCH_TESTS="delete.lua \
insert.lua \
oltp_simple.lua \
select.lua \
select_random_ranges.lua \
update_index.lua \
update_non_index.lua "


TEST_DIR="/usr/share/sysbench/tests/include/oltp_legacy"

host=$1
if [ -z $host ]; then echo "usage: $0 hostname" && exit 1; fi

for sysbench_test in $SYSBENCH_TESTS; do
  for threads in $NUM_THREADS; do
    echo "$threads threads"
    echo "test $sysbench_test"
    for table in $(mysql -B -N -h $host -u $MYSQL_USER -p$MYSQL_PASSWORD sbtest -e 'show tables;'); do 
      mysql -h $host -u $MYSQL_USER -p$MYSQL_PASSWORD sbtest -e "drop table $table;" 
    done
    sysbench \
      --mysql-host=$host \
      --db-driver=mysql \
      --mysql-user=$MYSQL_USER \
      --mysql-password=$MYSQL_PASSWORD \
      --oltp-table-size=$TABLE_SIZE \
      --time=$RUN_TIME \
      --max-requests=0 \
      --mysql-table-engine=InnoDB \
      --mysql-engine-trx=yes \
      --threads=$threads \
      ${TEST_DIR}/$sysbench_test \
      prepare
    
    sysbench \
      --mysql-host=$host \
      --db-driver=mysql \
      --mysql-user=$MYSQL_USER \
      --mysql-password=$MYSQL_PASSWORD \
      --oltp-table-size=$TABLE_SIZE \
      --time=$RUN_TIME \
      --max-requests=0 \
      --mysql-table-engine=InnoDB \
      --mysql-engine-trx=yes \
      --threads=$threads \
      ${TEST_DIR}/$sysbench_test \
      run
    
    sysbench \
      --mysql-host=$host \
      --db-driver=mysql \
      --mysql-user=$MYSQL_USER \
      --mysql-password=$MYSQL_PASSWORD \
      --threads=$threads \
      ${TEST_DIR}/$sysbench_test \
      cleanup
  
  done
done

echo -e "Done. You probably want to purge the binlogs now.\n\n"
