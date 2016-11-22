#!/bin/bash

account=`echo -n $1 | base64 -w 0`
container=`echo -n $2 | base64 -w 0`
storagekey=`echo -n $3 | base64 -w 0`

manifest_file=/tmp/pach.manifest

# Download the manifest template
wget https://raw.githubusercontent.com/jpoon/aurora_deploy/master/pachyderm/pach.manifest -O $manifest_file
# Substitute template variables
sed -i "s~\[ACCOUNT\]~$account~g" $manifest_file
sed -i "s~\[CONTAINER\]~$container~g" $manifest_file
sed -i "s~\[STORAGE-KEY\]~$storagekey~g" $manifest_file
# Start Pachyderm
kubectl create -f $manifest_file

echo "Pachyderm is now running and configured to auto-restart"
