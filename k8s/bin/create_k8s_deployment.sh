#!/bin/bash
NOW=`date +"%s"`

DNS_PREFIX=$1
RESOURCE_GROUP=$2
ADMIN_NAME=$3
SERVICE_PRINCIPAL_ID=$4
SERVICE_PRINCIPAL_SECRET=$5
SSH_KEYFILE=$6

AGENT_COUNT=4
AGENT_VM_SIZE="Standard_D2_v2"
VNET_NAME="$DNS_PREFIX""VNet"
KUBERNETES_SUBNET="$DNS_PREFIX""KubernetesSubnet"
GLUSTER_SUBNET="$DNS_PREFIX""GlusterSubnet"

SUBSCRIPTION_ID=`az account list | grep id | awk '{print $2}' | sed 's/,//' | sed 's/\"//g'`
SSH_KEY=`cat $SSH_KEYFILE`

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S_CONFIG_FILE=`echo $SCRIPT_DIR | sed 's/bin//'`k8s/config/kubernetesvnet.json
K8S_DEPLOYMENT_FILE=`echo $SCRIPT_DIR | sed 's/bin//'`k8s/config/kube-acsengine-$NOW.json

cat $K8S_CONFIG_FILE \
    | sed "s/@@RESOURCE_GROUP@@/$RESOURCE_GROUP/g" \
    | sed "s/@@DNS_PREFIX@@/$DNS_PREFIX/g" \
    | sed "s/@@SUBSCRIPTION_ID@@/$SUBSCRIPTION_ID/g" \
    | sed "s/@@AGENT_COUNT@@/$AGENT_COUNT/g" \
    | sed "s/@@AGENT_VM_SIZE@@/$AGENT_VM_SIZE/g" \
    | sed "s/@@VNET_NAME@@/$VNET_NAME/g" \
    | sed "s/@@KUBERNETES_SUBNET@@/$KUBERNETES_SUBNET/g" \
    | sed "s/@@ADMIN_NAME@@/$ADMIN_NAME/g" \
    | sed "s/@@SERVICE_PRINCIPAL_ID@@/$SERVICE_PRINCIPAL_ID/g" \
    | sed "s/@@SERVICE_PRINCIPAL_SECRET@@/$SERVICE_PRINCIPAL_SECRET/g" \
    | sed "s~@@SSH_KEY@@~$SSH_KEY~g" \
    > $K8S_DEPLOYMENT_FILE

cat $K8S_DEPLOYMENT_FILE