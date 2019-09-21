#!/bin/bash

FILE="/root/deploy_ss_server.sh"
if [ -f ${FILE} ]; then
	rm ${FILE}
fi

wget -N --directory-prefix=/root https://raw.githubusercontent.com/ivanstang/ss-config/master/deploy_ss_server.sh
bash ${FILE}