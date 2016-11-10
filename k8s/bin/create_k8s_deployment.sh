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

SUBSCRIPTION_ID=`azure account list --json | jq -r '.[0].id'`
RESOURCE_GROUP_REGION=`azure group show jmstest3 --json | jq -r '.location'`

SSH_KEY=`cat $SSH_KEYFILE`

SCRIPT_DIR=`dirname $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )`
K8S_CONFIG_FILE=`echo ${SCRIPT_DIR}/k8s/config/kubernetesvnet.json`
K8S_DEPLOYMENT_FILE=`echo ${SCRIPT_DIR}/k8s/config/kube-acsengine-$NOW.json`

echo "Generating acs-engine config."
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
    | tee $K8S_DEPLOYMENT_FILE

echo "Executing acs-engine to generate K8s config"
ACS_ENGINE_OUTPUT_DIR=`echo ${SCRIPT_DIR}/k8s/config/output/kube-config-$NOW`
ACS_ENGING_BIN=`echo ${SCRIPT_DIR}/bin/acs-engine`
$ACS_ENGING_BIN -artifacts $ACS_ENGINE_OUTPUT_DIR $K8S_DEPLOYMENT_FILE

echo "Setting up storage account for K8s artifacts"
K8S_STORAGE_ACCOUNT_NAME="$DNS_PREFIX""assetstore"
K8S_STORAGE_ACCOUNT_CONTAINER="$DNS_PREFIX""$NOW"
STORAGE_ACCOUNT_AVAILABLE=`azure storage account check --json "$K8S_STORAGE_ACCOUNT_NAME" | jq -r '.nameAvailable'`
if [ "$STORAGE_ACCOUNT_AVAILABLE" == "true" ]
then
    echo "Creating storage account"
    azure storage account create --location "$RESOURCE_GROUP_REGION" --resource-group "$RESOURCE_GROUP" --sku-name LRS --kind Storage "$K8S_STORAGE_ACCOUNT_NAME"
fi 
K8S_STORAGE_ACCOUNT_KEY=`azure storage account keys list --json --resource-group "$RESOURCE_GROUP" "$K8S_STORAGE_ACCOUNT_NAME" | jq -r '.[0].value'`
azure storage container create --account-name "$K8S_STORAGE_ACCOUNT_NAME" --account-key "$K8S_STORAGE_ACCOUNT_KEY" --permission Blob "$K8S_STORAGE_ACCOUNT_CONTAINER"

echo "Moving K8S deployment assets to storage account"
K8S_AZUREDEPLOY_JSON=`echo ${ACS_ENGINE_OUTPUT_DIR}/azuredeploy.json`
K8S_AZUREDEPLOY_PARAMETERS_JSON=`echo ${ACS_ENGINE_OUTPUT_DIR}/azuredeploy.parameters.json`
azure storage blob upload --json --account-name "$K8S_STORAGE_ACCOUNT_NAME" --account-key "$K8S_STORAGE_ACCOUNT_KEY" --file "$K8S_AZUREDEPLOY_JSON" --blobtype block --container "$K8S_STORAGE_ACCOUNT_CONTAINER" --blob azuredeploy.json
azure storage blob upload --json --account-name "$K8S_STORAGE_ACCOUNT_NAME" --account-key "$K8S_STORAGE_ACCOUNT_KEY" --file "$K8S_AZUREDEPLOY_PARAMETERS_JSON" --blobtype block --container "$K8S_STORAGE_ACCOUNT_CONTAINER" --blob azuredeploy.parameters.json
