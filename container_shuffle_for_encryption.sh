#!/bin/bash
# vim: set ts=4 sw=4 et
set -e

NAME="$1"

usage="$0 hostname"

if [[ -z "$NAME" ]]; then
    echo "name argument is required"
    echo -e $usage
    exit 1
fi

if [[ $NAME == "-h" || $NAME == "--help" ]]; then
    echo -e $usage
    exit 2
fi

echo -e "\nWARNING: this script could destroy data. I hope you know what you're doing. \n\n
    Before running this script, you should have already:\n
    1. Built a blank container named \"$NAME-new\"\n
    2. shut down the database and destroyed the container\n
    3. rsynced the original container to the new one\n\n
    If you have already done this, type \"yes\" to continue\n"

while read line; do 
    if [[ $line == "yes" ]]; then
        break
    fi
done

if [[ ! -d /containers/${NAME}-new/rootfs/ ]]; then
    echo "/containers/${NAME}-new/rootfs/ doesn't exist. Aborting."
    exit 1
fi

if virsh list | grep $NAME | grep -q running; then
    echo "Container $NAME is still running! Aborting."
    exit 1
fi

umount /containers/$NAME/rootfs/

#still haven't solved the leaky mount problem
for host in `virsh list | grep running | awk '{print $2}'`; do /opt/mysql_utils/bin/enter-container-ns $host umount /containers/${NAME}/rootfs >/dev/null 2>&1 || true; done

umount /containers/${NAME}-new/rootfs/

for host in `virsh list | grep running | awk '{print $2}'`; do /opt/mysql_utils/bin/enter-container-ns $host umount /containers/${NAME}-new/rootfs >/dev/null 2>&1 || true; done

mv /containers/$NAME /containers/${NAME}-old

mv /containers/${NAME}-new /containers/$NAME

mv /containers/$NAME/${NAME}-new.img /containers/$NAME/$NAME.img

sleep 3

dmsetup remove ${NAME}-new

# this is known to return an error
echo "(ignore the error \"Failed writing body\")"
clevis-luks-unlock -d /containers/$NAME/$NAME.img -n $NAME || true

mount -o noatime,_netdev /dev/mapper/$NAME /containers/$NAME/rootfs/

virsh start $NAME

sed -i -e "s/${NAME}-new/$NAME/g" /etc/fstab

sed -i -e "/^\/containers\/${NAME}/d" /etc/fstab

sed -i -e "s/${NAME}-new/$NAME/g" /etc/crypttab


echo -e "\nThe database should now be starting. Verify it looks ok, start slave if applicable.\n\n
If everything is ok, finish the cleanup by running:\n\n
rm -rf /containers/${NAME}-old/\n\n"

