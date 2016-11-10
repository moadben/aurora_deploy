#!/bin/bash
curl https://raw.githubusercontent.com/brendanacassidy/aurora_deploy/master/ingress/docker.presence.service > /etc/systemd/system/docker.presence.service
curl https://raw.githubusercontent.com/brendanacassidy/aurora_deploy/master/ingress/docker.topach.service > /etc/systemd/system/docker.topach.service
mkdir /etc/aurora
curl https://raw.githubusercontent.com/brendanacassidy/aurora_deploy/master/ingress/presence.conf > /etc/aurora/presence.conf
curl https://raw.githubusercontent.com/brendanacassidy/aurora_deploy/master/ingress/topach.conf > /etc/aurora/topach.conf
#echo "USER=$1" >> $conf_file
#echo "PASSWORD=$2" >> $conf_file
#echo "PACH_IP=$3" >>$conf_file
#echo "MONGO_URL=$4" >>$conf_file
#echo "DATABASE_NAME=$5" >>$conf_file
#echo "DBCOLLECTION=$6" >> $conf_file
systemctl daemon-reload
systemctl enable docker.presence.service
systemctl start docker.presence.service
systemctl enable docker.topach.service
systemctl start docker.topach.service
