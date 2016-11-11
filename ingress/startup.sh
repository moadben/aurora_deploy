#!/bin/bash

# Setup containers for ToPach & Presense
# Arguments:
#   $1: Docker Hub username to fetch packages from
#   $2: Docker Hub user password
#   $3: Address (IP:Port) for Pachyderm endpoint that ToPach & Presense should communicate with
#   $4: Full mongodb URL to write metadata to
#   $5: Name of metadata database 
#   $6: Name of metadata collection
#   $7: Port number that Presence is listening on
#   $8: Port number that ToPach is listening on
curl https://raw.githubusercontent.com/jpoon/aurora_deploy/master/ingress/docker.topach.service > /etc/systemd/system/docker.topach.service

# Emit our config file for ToPach service
mkdir /etc/aurora
conf_file=/etc/aurora/aurora.conf
echo "DOCKERHUB_USER=$1" > $conf_file
echo "DOCKERHUB_PASSWORD=$2" >> $conf_file
echo "PACH_IP=$3" >>$conf_file
echo "MONGO_URL=$4" >>$conf_file
echo "DB_NAME=$5" >>$conf_file
echo "DB_COLLECTION=$6" >> $conf_file
echo "PRESENCE_PORT=${7:-6429}" >> $conf_file
echo "TOPACH_PORT=${8:-4242}" >> $conf_file

systemctl daemon-reload
systemctl enable docker.topach.service
systemctl start docker.topach.service
