#!/bin/bash

# If primary interface is not eth0 or bond0, add its name as an argument to this script. 
# Sorry if it looks like this script was written on a Friday afternoon :)


INTERFACE=$1
if [[ -z "$INTERFACE" ]]
	then INTERFACE="eth0"
fi

function calculate {
	IPADDR=$(ip addr show dev $INTERFACE | grep 'inet' | awk '{print $2}' | awk -F/ '{print $1}')
}

calculate $INTERFACE

if [ -z $IPADDR ]; then
	INTERFACE="bond0"
	calculate $INTERFACE
fi
if [ -z $IPADDR ]; then
	echo "sorry, can't find the right Interface. Pass it as an argument to this script."
fi

# maybe someday you could pass an IP directly to the script

echo $IPADDR | awk -F. '{print $1*256^3 + $2*256^2 + $3*256 + $4}'
