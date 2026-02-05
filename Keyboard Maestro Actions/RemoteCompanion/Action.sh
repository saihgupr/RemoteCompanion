#!/bin/bash

if [ $KMPARAM_Device == 'iPad' ] 
then
	Device="ipad.local"
else
	Device="iphone.local"
fi

RESP=$(/bin/bash -c 'echo -n "${KMPARAM_Command}" | /usr/bin/nc -w 1 IP_ADDRESS 12340');

echo $RESP;