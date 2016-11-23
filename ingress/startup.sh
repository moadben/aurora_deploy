#!/bin/bash

# Setup containers for ToPach & Presense
# Arguments:
#   $1: Docker Hub username to fetch packages from
#   $2: Docker Hub user password
#   $3: Address (IP:Port) for Pachyderm endpoint that ToPach & Presense should communicate with
#   $4: Full mongodb URL to write metadata to
#   $5: Name of metadata database 
#   $6: Name of wave metadata collection
#   $7: Name of version metadata collection
#   $8: Port number that Presence is listening on
#   $9: Port number that ToPach is listening on
cp ./docker.presence.service /etc/systemd/system/docker.presence.service
cp ./docker.topach.service /etc/systemd/system/docker.topach.service
cp ./docker.parse.service /etc/systemd/system/docker.parse.service


# Emit our config file for services
mkdir /etc/aurora
conf_file=/etc/aurora/aurora.conf
echo "DOCKERHUB_USER=$1" > $conf_file
echo "DOCKERHUB_PASSWORD=$2" >> $conf_file
echo "PACH_IP=$3" >> $conf_file
echo "MONGO_URL=$4" >> $conf_file
echo "DB_NAME=$5" >> $conf_file
echo "DB_WAVE_COLN=$6" >> $conf_file
echo "DB_VERSION_COLN=$7" >> $conf_file
echo "PRESENCE_PORT=${8:-6429}" >> $conf_file
echo "TOPACH_PORT=${9:-4242}" >> $conf_file
echo "GF_DOCKER_LOGIN_SERVER=aurora-itadministrationgeneralfusi.azurecr.io" >> $conf_file
echo "GF_DOCKER_REG_HOST=aurora-itadministrationgeneralfusi.azurecr.io" >> $conf_file


systemctl daemon-reload
systemctl enable docker.presence.service
systemctl start docker.presence.service
sleep 5s
systemctl enable docker.topach.service
systemctl start docker.topach.service
sleep 5s
systemctl enable docker.parse.service
systemctl start docker.parse.service
