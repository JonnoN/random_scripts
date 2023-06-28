#!/bin/bash
# vim: set ts=4 sw=4 et
set -e

#some defaults
NETMASK="255.255.255.0"
BRIDGE="br1000"
ENCRYPTED="yes"

# throttle speed for disk image creation
DD_THROTTLE="50m"

KEY_PASS="temppass4setup"

ARGS=`getopt -o hn:s:v:i:m:g:b:a:BeEdDt:N --long help,name:,size:,version:,ip:,netmask:,gateway:,bridge:,app:,blank,encrypted,not-encrypted,dry-run,debug,throttle:,no-throttle -n 'create_libvirt_lxc_app_guest.sh' -- "$@"`
eval set -- "$ARGS"

usage="$0\n
Required arguments:\n
\t--name, -n \t\t Name\n
\t--size, -s \t\t Size [small, medium, large, xlarge]\n
Required arguments (except in Blank mode):\n
\t--version, -v \t\t MySQL/MariaDB version (\"10.3.11-mariadb\")\n
\t--ip, -i \t\t IP Address\n
\t--gateway, -g \t\t Gateway IP Address\n
\t--app, -a \t\t App name\n
Optional arguments:\n
\t--netmask, -m \t\t Netmask (\"$DEFAULT_NETMASK\")\n
\t--bridge, -b \t\t Bridge name (\"$DEFAULT_BRIDGE\")\n
\t--encrypted, -E \t Encrypted image\n
\t--not-encrypted, -e \t Unencrypted image\n
\t--blank, -B \t\t Blank filesystem\n
\t--dry-run, -d \t\t Dry Run\n
\t--throttle, -t \t\t Throttle speed in MB/s\n
\t--no-throttle, -N \t\t disable the speed throttle\n
\t--debug, -D \t\t Debug\n
\t--help, -h \t\t Help (this text)
\n
"

echo ""
while true; do
    case "$1" in
        -h|--help) echo -e $usage; exit 0 ;;
        -n|--name) NAME=$2 ; shift 2 ;;
        -s|--size) SIZE=$2 ; shift 2 ;;
        -v|--version) VERSION=$2 ; shift 2 ;;
        -i|--ip) IPADDR=$2 ; shift 2 ;;
        -m|--netmask) NETMASK=$2 ; shift 2 ;;
        -g|--gateway) GATEWAY=$2 ; shift 2 ;;
        -b|--bridge) BRIDGE=$2 ; shift 2 ;;
        -a|--app) APPNAME=$2 ; shift 2 ;;
        -B|--blank) BLANK="yes" ; shift ;;
        -E|--encrypted) ENCRYPTED="yes" ; shift ;;
        -e|--not-encrypted) ENCRYPTED="no" ; shift ;;
        -d|--dry-run) DRY_RUN="yes" ; shift ;;
        -t|--throttle) DD_THROTTLE="${2}m" ; shift 2 ;;
        -N|--no-throttle) DD_THROTTLE="1000m" ; shift ;;
        -D|--debug) DEBUG="yes" ; shift ;;
        --) shift ; break ;;
        *) echo "Error parsing arguments" ; exit 1 ;;
    esac
done

if [[ $DEBUG == "yes" ]]; then
    echo "name      = $NAME"
    echo "size      = $SIZE"
    echo "version   = $VERSION"
    echo "ip        = $IPADDR"
    echo "netmask   = $NETMASK"
    echo "gateway   = $GATEWAY"
    echo "bridge    = $BRIDGE"
    echo "app       = $APPNAME"
    echo "blank     = $BLANK"
    echo "encrypted = $ENCRYPTED"
    echo "dry-run   = $DRY_RUN"
fi

if [[ -z "$NAME" ]]; then
    echo "--name argument is required"
    echo -e $usage
    exit 1;
fi

if [[ -z $SIZE ]]; then
    echo "--size argument is required"
    echo -e $usage
    exit 1
fi

SIZES=(small medium large xlarge)
sizematch=0
for foo in "${SIZES[@]}"; do
        if [[ $foo = $SIZE ]]; then
            sizematch=1
            break
    fi
done
if [[ $sizematch = 0 ]]; then
    echo -e $usage
    exit 1
fi

case "$SIZE" in
    small)
        mem=4096000
        disk=128000
        cores=1
        ;;
    medium)
        mem=8192000
        disk=256000
        cores=2
        ;;
    large)
        mem=16384000
        disk=512000
        cores=4
        ;;
    xlarge)
        mem=24576000
        disk=819200
        cores=4
        ;;
esac

if [[ ! $DD_THROTTLE =~ [0-9]*m$ ]]; then
    echo "--throttle requires argument number of MB/s (default 50)"
    exit 1
fi

if [[ $BLANK != "yes" ]]; then
    if [[ -z $VERSION ]]; then
        echo "--version argument is required"
        echo -e $usage
        exit 1
    fi
    if [[ ! -d /opt/sharedb-software/$VERSION ]]; then
        echo -ne "version $VERSION not found. \nAvailable mysql versions: "
        ls /opt/sharedb-software
        exit 1
    fi

    if [[ -z "$APPNAME" ]]; then
        echo "No App Name specified. Using default 'sharedb'"
        APPNAME="sharedb"
    fi

    if [[ ! -f /opt/mysql_utils/setup/cnf/app/${APPNAME}.cnf ]]; then
        echo "App config not found at /opt/mysql_utils/setup/cnf/app/${APPNAME}.cnf. Exiting."
        exit 1
    fi

    if [[ -z $IPADDR ]]; then
        echo "--ip argument is required"
        echo -e $usage
        exit 1
    fi

    if [[ -z $GATEWAY ]]; then
        echo "--gateway argument is required"
        echo -e $usage
        exit 1
    fi
fi

libvirt_xml="/containers/$NAME/libvirt.xml"
fs_image="/containers/$NAME/$NAME.img"
rootfs="/containers/$NAME/rootfs"

if [[ -e $rootfs ]]; then
    echo "container $NAME already exists. Exiting."
    exit 1
fi

if [[ $DRY_RUN != "yes" ]]; then
    text="Notice: build of $NAME on $(hostname -s) Started."
    wget --timeout=10 --tries=1 -nv --output-document=/dev/null "http://squeaky-api:18080/spam?dest=%23dbas-notifications&msg=$text"
fi

function create_disk_image {

    if [[ $DRY_RUN == "yes" ]]; then
        echo "would create disk image $fs_image"
        return
    fi

    echo "creating disk image $fs_image"

    mkdir -p $rootfs

    dd iflag=nonblock if=/dev/zero bs=1048576 count=$disk 2>/dev/null | ionice -c3 pv -p -e -r -s ${disk}m -L $DD_THROTTLE > $fs_image

    if [[ $ENCRYPTED == "yes" ]]; then
        echo "$KEY_PASS" | cryptsetup -q luksFormat --type luks1 $fs_image
        echo "$KEY_PASS" | cryptsetup luksOpen $fs_image $NAME
        luksmeta init -d $fs_image -f
        register_tang $fs_image $KEY_PASS
        fs_image="/dev/mapper/$NAME"
    fi
}

function create_filesystem {

    if [[ $DRY_RUN == "yes" ]]; then
        echo "would create filesystem on $fs_image"
        return
    fi

    mkfs.ext4 -E nodiscard -F -m 1.0 $fs_image
    tune2fs -c 0 $fs_image
    mount -o loop,noatime $fs_image $rootfs || (echo "failed to mount image!!"; exit 1)
    if [[ $ENCRYPTED == "yes" ]]; then
        echo "$NAME /containers/$NAME/$NAME.img none _netdev" >> /etc/crypttab
        echo "$fs_image $rootfs ext4 noatime,_netdev 0 0" >> /etc/fstab
    else
        echo "$fs_image $rootfs ext4 rw,loop,noatime 0 0" >> /etc/fstab
    fi
}

function install_mysql {

    if [[ $DRY_RUN == "yes" ]]; then
        echo "would install mysql/mariadb $VERSION"
        return
    fi

    mkdir -p $rootfs/root
    mkdir -p $rootfs/db_data
    mkdir -p $rootfs/db_log
    mkdir -p $rootfs/var/lib/mysql
    mkdir -p $rootfs/var/log/mysql
    mkdir -p $rootfs/var/lock/subsys
    mkdir -p $rootfs/etc/mysql
    mkdir -p $rootfs/etc/check_mk
    mkdir -p $rootfs/etc/init.d
    mkdir -p $rootfs/opt/mysql
    mkdir -p $rootfs/tmp
    chmod 1777 $rootfs/tmp
    mkdir -p $rootfs/mnt

    cp /etc/init.d/functions $rootfs/etc/init.d/

    tar xzf /opt/sharedb-software/$VERSION/*.tar.gz -C $rootfs/opt/
    sourcedir=$(find $rootfs/opt -maxdepth 1 -type d \( -iname 'mysql-*' -o -iname 'mariadb-*' \) -print -quit)
    if [[ ! -z "$sourcedir" ]]; then
        mv $sourcedir/* $rootfs/opt/mysql/
    else
        echo -e "unable to find source directory (new version or flavor?) Exiting.\nYou probably have some cleanup to do in $rootfs"
        exit 1
    fi
    echo $VERSION > $rootfs/opt/mysql/VERSION

    # first boot
    echo "creating first-boot.sh"
    cat <<EOF > $rootfs/root/first-boot.sh
#!/bin/bash
/opt/mysql_utils/setup/sharedb_install.sh $(echo $VERSION | cut -d. -f1,2) >> /root/sharedb_install.log 2>&1
EOF

    chmod 755 "$rootfs/root/first-boot.sh"


    # init script
    echo "Creating init for guest"
    cat <<EOF > $rootfs/root/lxc_guest_init.sh
#!/bin/bash
export PATH="/opt/mysql/bin:$PATH:/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin:/root/bin"
export PS1='[\u@\h \W \[\033[31m\]DO NOT EXIT \[\033[0m\]]# '
export HOME="/root"

/sbin/ifconfig eth0 $IPADDR netmask $NETMASK
/sbin/route add default gw $GATEWAY

/bin/hostname $NAME.domain.com

if [ -f /etc/init.d/mysql ]; then /etc/init.d/mysql start; fi
if [ -f /opt/mysql_utils/setup/files/xinetd.d-check_mk_sharedb ]; then xinetd -f /opt/mysql_utils/setup/files/xinetd.d-check_mk_sharedb -stayalive -pidfile /var/lock/subsys/xinetd.pid; fi
if [ -f /root/first-boot.sh ]; then /root/first-boot.sh && rm /root/first-boot.sh; fi

/bin/bash
EOF
    chmod 755 "$rootfs/root/lxc_guest_init.sh"

    # libvirt.xml
    echo "Creating libvirt config: $libvirt_xml"
    cat <<EOF > $libvirt_xml
<domain type="lxc">
  <name>$NAME</name>
  <memory>$mem</memory>
  <os>
    <type>exe</type>
    <init>/root/lxc_guest_init.sh</init>
  </os>
  <vcpu>$cores</vcpu>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>destroy</on_crash>
  <devices>
    <emulator>/usr/libexec/libvirt_lxc</emulator>

    <filesystem type='mount' accessmode='passthrough'>
      <source dir='/'/>
      <target dir='/'/>
      <readonly/>
    </filesystem>

    <filesystem type="mount">
      <source dir="$rootfs/root"></source>
      <target dir="/root">
    </target></filesystem>

    <filesystem type="mount">
      <source dir="$rootfs/db_data"></source>
      <target dir="/db_data">
    </target></filesystem>

     <filesystem type="mount">
      <source dir="$rootfs/db_log"></source>
      <target dir="/db_log">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/var/lib/mysql"></source>
      <target dir="/var/lib/mysql">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/etc/mysql"></source>
      <target dir="/etc/mysql">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/etc/check_mk"></source>
      <target dir="/etc/check_mk">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/etc/init.d"></source>
      <target dir="/etc/init.d">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/var/log/mysql"></source>
      <target dir="/var/log/mysql">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/opt/mysql"></source>
      <target dir="/opt/mysql">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/var/lock/subsys"></source>
      <target dir="/var/lock/subsys">
    </target></filesystem>

   <filesystem type="mount">
      <source dir="$rootfs/tmp"></source>
      <target dir="/tmp">
    </target></filesystem>

    <interface type="bridge">
      <source bridge="$BRIDGE"/>
    </interface>
    <console type="pty">
  </console></devices>
  <seclabel type='none'/>
</domain>
EOF

    # sharedb.cfg
    echo "Creating sharedb.cfg"
    cat <<EOF > $rootfs/var/lib/mysql/sharedb.cfg
#$SIZE instance
NAME=$NAME
MEM=$mem
CPU=$cores
IPADDR=$IPADDR
APPNAME=$APPNAME
EOF

}

function start_container {

    if [[ $DRY_RUN == "yes" ]]; then
        echo "would define and start container $NAME"
        return
    fi

    virsh define "$libvirt_xml"
    rm "$libvirt_xml"
    echo "Starting container..."
    virsh start $NAME

}

#workaround LDAP group lookup problem 
getent group DBAs >/dev/null

create_disk_image
create_filesystem
if [[ $BLANK != "yes" ]]; then
    install_mysql
    start_container
fi

echo
echo "Done."

if [[ $DRY_RUN != "yes" ]]; then
    text="Notice: build of $NAME on $(hostname -s) is complete."
    wget --timeout=10 --tries=1 -nv --output-document=/dev/null "http://squeaky-api:18080/spam?dest=%23dbas-notifications&msg=$text"
fi

