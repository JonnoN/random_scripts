#!/bin/sh

DEFDIR="/opt/mysql_utils/setup"
CNFDIR=$DEFDIR/cnf
THISDC=`hostname | cut -d'-' -f1`
VERSION=$1
FLAVOR=$2
CENTOS_MAJOR_VERSION=$(facter os.distro.release.major)

if [ -z "$VERSION" ]; then
  VERSION=10.3
fi
if [ -z "$FLAVOR" ]; then
  FLAVOR=mariadb
fi
if [ "$FLAVOR" = maria ]; then
  FLAVOR=mariadb
fi

if [ "$FLAVOR" = mysql ]; then
  if (( $( echo "$VERSION > 9.9" | bc -l ) )); then
    echo "The version '$VERSION' you specified looks like a MariaDB one, assuming you meant that"
    FLAVOR=mariadb
  fi
elif [ "$FLAVOR" = mariadb ]; then
  :
else
  echo >&2 "ERROR: Do not know how to install flavor '$FLAVOR'"
  exit 1
fi

function check_error {
  ERRCODE=$?
  if [ $ERRCODE -ne 0 ] ; then
    echo "`date` $PNAME failed, exiting."
    exit $ERRCODE
  else
    echo "`date` $PNAME succeeded."
  fi
}

function check_configs {
  PNAME="Check for configuration files"
  HNAME=`hostname -s`
  APPNAME=`cat $CNFDIR/server/$HNAME.cnf | grep "^# AppName" | cut -d':' -f2`
  if [ ! -e $CNFDIR/server/$HNAME.cnf ] ; then
    PNAME="$PNAME ($HNAME)"
    false
  elif [ ! -e $CNFDIR/app/$APPNAME.cnf ] ; then
    PNAME="$PNAME ($APPNAME)"
    false
  else
    true
  fi
  check_error
}

function create_user {
  PNAME="MySQL Group & User creation"
  groupadd -g 27 mysql && \
  useradd -c "MySQL User" -g 27 -u 27 -r -d /var/lib/mysql mysql
  check_error
}

function create_directories {
  PNAME="Create directory structure"
  mkdir /etc/mysql && \
  chown -R mysql:DBAs /etc/mysql && \
  mkdir -p /db_data/mysql && \
  chown -R mysql:DBAs /db_data/mysql && \
  mkdir -p /db_log/mysql/grants && \
  chown -R mysql:DBAs /db_log/mysql && \
  mkdir -p /etc/maatkit && \
  chown -R root:DBAs /etc/maatkit && \
  mkdir -p /var/log/mysql && \
  chown -R mysql:DBAs /var/log/mysql
  check_error
}

function copy_configs {
  PNAME="Copying MySQL configuration files"
  cp $CNFDIR/my.cnf /etc/my.cnf && \
  cp $CNFDIR/dir/default.cnf /etc/mysql/. && \
  cp $CNFDIR/version/$( echo $VERSION | tr '.' '_')* /etc/mysql/. 
  check_error
}

function copy_memory_config {
  PNAME="Determining memory size"
  MEM_TOTAL=`cat /proc/meminfo | grep MemTotal | awk '{print $2}'`
  MEM_TOTAL=`expr $MEM_TOTAL / 1024`
  if   [ $MEM_TOTAL -ge 63000 ] ; then MEM_FILE=64G
  elif [ $MEM_TOTAL -ge 31000 ] ; then MEM_FILE=32G
  elif [ $MEM_TOTAL -ge 15000 ] ; then MEM_FILE=16G
  elif [ $MEM_TOTAL -ge 7900 ]  ; then MEM_FILE=8G
  elif [ $MEM_TOTAL -ge 3900 ]  ; then MEM_FILE=4G
  elif [ $MEM_TOTAL -ge 1900 ]  ; then MEM_FILE=2G
  else
    MEM_FILE=512M
  fi
  cp $CNFDIR/memory/$MEM_FILE.cnf /etc/mysql/. 
  check_error
}

function copy_server_config {
  PNAME="Copying server configs"
  cp $CNFDIR/server/$HNAME.cnf /etc/mysql/zz_${HNAME}.cnf
  check_error
}

function install_mysql {
  PNAME="Installing MySQL"
if [ "$FLAVOR" = "mysql" ]; then

  # do install
  if [[ $VERSION = 5.7 ]]; then
    yum -y localinstall mysql-community-server-5.7*.rpm mysql-community-client-5.7*.rpm mysql-community-common-5.7*.rpm mysql-community-libs-5.7*.rpm mysql-community-libs-compat-5.7*.rpm || \
      (echo "not putting 5.7 in the repo. Place the rpms in the current directory (presumably /root)." && \
       echo "perhaps try 'wget https://dev.mysql.com/get/Downloads/MySQL-5.7/mysql-5.7.25-1.el7.x86_64.rpm-bundle.tar'" && exit 1)
  else
    # I am assuming CentOS 7 for 'yum swap' here - but no-one would be so crazy
    # as to deploy a new database on CentOS 6 at this point, right?

    yum -q -y --setopt=obsoletes=0 swap -- mariadb-libs MariaDB-common MariaDB-shared -- "MySQL-client-${VERSION}*" "MySQL-shared-compat-${VERSION}*" "MySQL-server-${VERSION}*" "MySQL-shared-${VERSION}*"

  fi

  # setup datadir/password
  if [[ $VERSION = 5.6 ]]; then
    echo "attempting to work around Oracle's bullshit ( http://bugs.mysql.com/bug.php?id=72724 ) "
    rm -v /usr/my.cnf
    mv /var/lib/mysql/* /db_data/mysql/
    service mysql start
    TEMPPW=$(foo=`cat /root/.mysql_secret`; echo ${foo##* })
    mysql --connect-expired-password -p$TEMPPW -e "SET PASSWORD = '';"
    service mysql stop
  fi
  if [[ $VERSION = 5.7 ]]; then
    mysqld --initialize-insecure --user=mysql --datadir=/db_data/mysql/
  fi


  elif [ "$FLAVOR" = "mariadb" ]; then
    #Centos 6,7
    if [[ $CENTOS_MAJOR_VERSION -lt 8 ]]; then
      yum -q -y --setopt=obsoletes=0 install "MariaDB-common-${VERSION}*" "MariaDB-client-${VERSION}*" "MariaDB-compat-${VERSION}*" "MariaDB-server-${VERSION}*"
  
    #Centos 8
    elif [[ $CENTOS_MAJOR_VERSION -eq 8 ]]; then
      # dnf swap does not work for multiple packages any more.
      # remove useless packages that inappropriately provide libmariadb:
      rpm -e --nodeps mariadb-connector-c mariadb-connector-c-config >/dev/null || true
      # disable the builtin AppStream modules:
      yum module disable mysql
      yum module disable mariadb
      # install packages from our own repo:
      yum -q -y --setopt=obsoletes=0 install "MariaDB-common-${VERSION}*" "MariaDB-client-${VERSION}*" "MariaDB-shared-${VERSION}*" "MariaDB-server-${VERSION}*"
      mysql_install_db
      #enable start on boot
      systemctl enable mariadb
    fi
  fi

  check_error
}

function install_third_party {
  PNAME="Installing 3rd party tools"
  yum -q -y install maatkit innotop pwgen 
  check_error
}

function install_timezones {
  PNAME="Install Time Zones"
  mysql_tzinfo_to_sql /usr/share/zoneinfo | mysql -s --force mysql
  check_error
}

function install_maatkit_conf {
  PNAME="Creating maatkit config"
  echo -e 'user=adm_maatkit\npassword=maatkit_password' > /etc/maatkit/maatkit.conf
  check_error
}

function run_queries {
  PNAME="Running MySQL queries"
  mysql < $DEFDIR/install.sql
  check_error
}

function stop_mysql {
  PNAME="Stop MySQL"
  mysqladmin shutdown
  check_error
}

function copy_app_config {
  PNAME="Copy application config"
  if [ "$APPNAME" != "" ] ; then
    cp $CNFDIR/app/$APPNAME.cnf /etc/mysql/z_${APPNAME}.cnf
  fi
  if grep -qi innodb_log_file_size /etc/mysql/*; then
    if ! pgrep mysqld >/dev/null ; then
      rm -f /db_log/mysql/ib_logfile*
    fi
  fi 
  check_error
}

function setup_ownership {
  PNAME="Setup config ownership"
  chmod 640 /etc/my.cnf && \
  chmod 640 /etc/mysql/*.cnf && \
  chown mysql:DBAs /etc/my.cnf && \
  chown -R mysql:DBAs /etc/mysql
  check_error
}

function start_mysql {
  PNAME="Start MySQL"
  if [[ $VERSION == 5.1 || $VERSION == 5.7 ]]; then
    service_name="mysqld"
  else
    service_name="mysql"
  fi
  service $service_name start
  check_error
}

function set_root_password {
  PNAME="Setting up root password"
  MPWORD=`pwgen -1Bcn 16` && \
  mysql -B --skip-column-names -e "SET PASSWORD = PASSWORD('$MPWORD')" && \
  echo -e "[client]\nuser=root\npassword=$MPWORD" > ~root/.my.cnf && \
  chmod 400 ~root/.my.cnf
  check_error
}

function set_checkmk_password {
  PNAME="setting up mon_check_mk password"
  CMKPW=`pwgen -1Bcn 16` && \
  ECMKPW=`mysql -B --skip-column-names -e"SELECT PASSWORD('$CMKPW')"` && \
  mysql -e "GRANT PROCESS, SUPER, REPLICATION CLIENT ON *.* TO 'mon_check_mk'@'localhost' IDENTIFIED BY PASSWORD '$ECMKPW';" && \
  mkdir -p /etc/check_mk && \
  echo -e "[client]\nuser=mon_check_mk\npassword=$CMKPW" > /etc/check_mk/mysql.cfg && \
  chmod 400 /etc/check_mk/mysql.cfg
  check_error
}

check_configs
create_user
create_directories
copy_configs
copy_memory_config
copy_server_config
install_mysql
install_third_party
install_maatkit_conf
start_mysql
install_timezones
run_queries
stop_mysql
copy_app_config
setup_ownership
start_mysql
set_root_password
set_checkmk_password
