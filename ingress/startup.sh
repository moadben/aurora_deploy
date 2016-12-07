#!/bin/bash

# Setup ingress node docker environment
# Arguments:
#   $1: Login server for docker registry
#   $2: Docker username
#   $3: Docker password
#   $4: Docker registry where service images reside
#   $5: Tag of server docker images to deploy (and track on restart) 
#   $6: Address (IP:Port) for Pachyderm endpoint
#   $7: URL of Mongo DB for metadata
#   $8: Name of metadata database 
#   $9: Name of metadata database wave collection
#   $10: Name of metadata database version collection
#   $11: Port number for presence to listen on
#   $12: Port number for topach to listen on

# Create config file for services
mkdir /etc/aurora
conf_file=/etc/aurora/aurora.conf

# Write arguments to config file
# (Docker args prefixed with "GF" to avoid conflict with docker env vars)
echo "GF_DOCKER_LOGIN_SERVER=${1}" > $conf_file
echo "GF_DOCKER_USER=${2}" >> $conf_file
echo "GF_DOCKER_PASSWORD=${3}" >> $conf_file
echo "GF_DOCKER_REGISTRY=${4}" >> $conf_file
echo "GF_DOCKER_TAG=${5}" >> $conf_file
echo "PACHYDERM_ADDRESS=${6}" >> $conf_file
echo "DB_MONGO_URL=${7}" >> $conf_file
echo "DB_NAME=${8}" >> $conf_file
echo "DB_WAVE_COLLECTION=${9}" >> $conf_file
echo "DB_VERSION_COLLECTION=${10}" >> $conf_file
echo "PRESENCE_PORT=${11}" >> $conf_file
echo "TOPACH_PORT=${12}" >> $conf_file
echo "CREAM_PORT=${13}" >> $conf_file
echo "API_PORT=${14}" >> $conf_file
echo "REDIS_URL=${15}" >> $conf_file
echo "AURORA_BASE_URL={$16}" >> $conf_file

# Copy systemd service files for the various docker images
cp ./docker.presence.service /etc/systemd/system/docker.presence.service
cp ./docker.topach.service /etc/systemd/system/docker.topach.service
cp ./docker.parse.service /etc/systemd/system/docker.parse.service
cp ./docker.cream.service /etc/systemd/system/docker.cream.service
cp ./docker.api.service /etc/systemd/system/docker.api.service
systemctl daemon-reload

# Start presence service
systemctl enable docker.presence.service
systemctl start docker.presence.service
sleep 5s

# Start topach service
systemctl enable docker.topach.service
systemctl start docker.topach.service
sleep 5s

# Start parse service
systemctl enable docker.parse.service
systemctl start docker.parse.service
sleep 5s

# Start parse service
systemctl enable docker.cream.service
systemctl start docker.cream.service
sleep 5s

# Start parse service
systemctl enable docker.api.service
systemctl start docker.api.service
