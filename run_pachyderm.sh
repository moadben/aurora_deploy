#!/bin/bash

account=$1
container=$2
storagekey=$3

manifest_file=/tmp/pach.manifest

# Download the manifest template
wget https://raw.githubusercontent.com/jpoon/aurora_deploy/master/pach.manifest -O $manifest_file
# Substitute template variables
sed -i "s/\[ACCOUNT\]/$account/g" $manifest_file
sed -i "s/\[CONTAINER\]/$container/g" $manifest_file
sed -i "s/\[STORAGE-KEY\]/$storagekey/g" $manifest_file
# Start Pachyderm
kubectl create -f $manifest

echo "Pachyderm is now running and configured to auto-restart"
