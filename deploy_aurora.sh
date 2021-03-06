#!/bin/bash

## Shared config information
BASENAME=${1}
RESOURCE_GROUP=${2}
REGION=${3}
ADMIN_NAME=${4}
SSH_KEYFILE=${5:-'~/.ssh/id_rsa.pub'}
SERVICE_PRINCIPAL_SECRET=${6}
DEPLOYMENT_STORAGE_BASEURI=${7}
DEPLOYMENT_STORAGE_SAS=${8}
ACR_RESOURCE_GROUP=${9}
ACR_NAME=${10}
DOCKER_REGISTRY=${11}
K8S_AGENT_COUNT=${12:-4}
K8S_AGENT_VM_SIZE=${13:-'Standard_D2_v2'}
ACS_ENGINE_CONFIG_FILE=${14}
BASE_DEPLOYMENT_URI=${15}
SPN_NAME=${16:-'http://Aurora_K8s_Controller'}

if [[ -z "$BASE_DEPLOYMENT_URI" ]]; then  
    BASE_DEPLOYMENT_URI="https://raw.githubusercontent.com/moadben/aurora_deploy/$(git rev-parse HEAD)/"  
fi  

## Pre-requisites
hash jq >/dev/null || (echo "Can not find the 'jq' program, please install it." >&2 && exit 1)
hash azure >/dev/null || (echo "Can not find the 'azure' program, please install it." >&2 exit 1)

## Azure Login
azure account show &>/dev/null || azure login
SUBSCRIPTION_ID=$(azure account show --json | jq -r '.[].id')

NOW=$(date +"%s")

## Statically assign IP addresses to master node(s)
K8S_MASTER_IP_START="10.0.1.100"

## Create the Service Principal
echo "--- Create Service Principal"
SPN_OBJECTID=$(azure ad sp show -n "$SPN_NAME" --json | jq -r '.[].objectId')
if [[ ! $SPN_OBJECTID ]]; then
    # The Application could theoretically already exist
    SPN_APPID=$(azure ad app show -i "$SPN_NAME" --json | jq -r '.[0].appId')
    if [[ ! $SPN_APPID ]]; then 
        SPN_APPID=$(azure ad app create -n "Aurora K8s Controller" -i "$SPN_NAME" -m "$SPN_NAME" -p "$SERVICE_PRINCIPAL_SECRET" --json | jq -r '.appId')
    fi
    SPN_OBJECTID=$(azure ad sp create -a "$SPN_APPID" --json | jq -r '.objectId')
else
    SPN_APPID=$(azure ad sp show -o "$SPN_OBJECTID" --json | jq -r '.[0].appId')
fi
if [[ ! $SPN_APPID ]]; then
    echo "FATAL: Failed to create/update required service principal." >&2 && exit 1
fi

BASE_OUT_DIR="/tmp/deploy_aurora/$NOW"
mkdir -p "$BASE_OUT_DIR"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S_DEPLOYMENT_FILE="$BASE_OUT_DIR/kube-acsengine.json"
ACS_ENGINE_OUTPUT_DIR="$BASE_OUT_DIR/kube-config"

echo "--- Create SSH Keys"
SSH_KEY=$(cat "$SSH_KEYFILE")
# Generate keypair for internal VM communication
INTERNAL_KEY_FILE=$BASE_OUT_DIR/id_rsa
ssh-keygen -f "$INTERNAL_KEY_FILE" -N ""
INTERNAL_SSH_PRIVATE_KEY=$(cat "$INTERNAL_KEY_FILE" | sed '$d' | sed '1d' | tr -d '\n')
INTERNAL_SSH_PUBLIC_KEY=$(cat "$INTERNAL_KEY_FILE".pub | tr -d '\n')

echo "--- Generating Configs for ACS-Engine"
if [[ ! $ACS_ENGINE_CONFIG_FILE ]]; then
    ACS_ENGINE_CONFIG_FILE=$SCRIPT_DIR/k8s/config/kubernetesvnet.json
fi
cat "$ACS_ENGINE_CONFIG_FILE" \
    | sed "s/@@RESOURCE_GROUP@@/$RESOURCE_GROUP/g" \
    | sed "s/@@DNS_PREFIX@@/$BASENAME/g" \
    | sed "s/@@SUBSCRIPTION_ID@@/$SUBSCRIPTION_ID/g" \
    | sed "s/@@AGENT_COUNT@@/$K8S_AGENT_COUNT/g" \
    | sed "s/@@AGENT_VM_SIZE@@/$K8S_AGENT_VM_SIZE/g" \
    | sed "s/@@VNET_NAME@@/$BASENAME-vnet/g" \
    | sed "s/@@KUBERNETES_SUBNET@@/kubernetes/g" \
    | sed "s/@@K8S_MASTER_IP_START@@/$K8S_MASTER_IP_START/g" \
    | sed "s/@@ADMIN_NAME@@/$ADMIN_NAME/g" \
    | sed "s/@@SERVICE_PRINCIPAL_ID@@/$SPN_APPID/g" \
    | sed "s/@@SERVICE_PRINCIPAL_SECRET@@/$SERVICE_PRINCIPAL_SECRET/g" \
    | sed "s~@@SSH_KEY@@~$INTERNAL_SSH_PUBLIC_KEY~g" \
    | tee "$K8S_DEPLOYMENT_FILE"

echo "--- Generating Kubernetes Configs"
"$SCRIPT_DIR/k8s/bin/linux/acs-engine" -artifacts "$ACS_ENGINE_OUTPUT_DIR" "$K8S_DEPLOYMENT_FILE"

echo "--- ACS-Engine: Moving ACS K8S deployment assets to storage account"
# Parameter Link files need a slightly different format
# Also add the nameSuffix parameter so that we can predict the name of resources created by the acs-engine generated template
cat "$ACS_ENGINE_OUTPUT_DIR"/azuredeploy.parameters.json | jq '
  .nameSuffix={"value":"'$NOW'"} | 
  {
      "$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#", 
      "contentVersion": "1.0.0.0", 
      "parameters": . 
  }' > "$ACS_ENGINE_OUTPUT_DIR"/acs-azuredeploy.parameters.json

if [[ $DEPLOYMENT_STORAGE_SAS && ${DEPLOYMENT_STORAGE_SAS:0:1} != '?' ]]; then
    DEPLOYMENT_STORAGE_SAS="?$DEPLOYMENT_STORAGE_SAS"
fi
DEPLOYMENT_STORAGE_BASEURI="${DEPLOYMENT_STORAGE_BASEURI%%+(/)}"
ACS_TEMPLATE_URI="$DEPLOYMENT_STORAGE_BASEURI/$NOW/azuredeploy.json$DEPLOYMENT_STORAGE_SAS"
ACS_PARAMETERS_URI="$DEPLOYMENT_STORAGE_BASEURI/$NOW/azuredeploy.parameters.json$DEPLOYMENT_STORAGE_SAS"

curl -X PUT -d @"$ACS_ENGINE_OUTPUT_DIR/azuredeploy.json" -H "x-ms-blob-type: BlockBlob" "$ACS_TEMPLATE_URI"
curl -X PUT -d @"$ACS_ENGINE_OUTPUT_DIR/acs-azuredeploy.parameters.json" -H "x-ms-blob-type: BlockBlob" "$ACS_PARAMETERS_URI"

echo --- Invoking ARM E2E template
BASE_DEPLOYMENT_URI="${BASE_DEPLOYMENT_URI%%+(/)}/"
# Generate parameters file
cat << EOF > "$BASE_OUT_DIR"/orchestrator.parameters.json
{
  "baseName": {
    "value": "$BASENAME"
  },
  "adminUsername": {
    "value": "$ADMIN_NAME"
  },
  "sshKeyData": {
    "value": "$SSH_KEY"
  },
  "dockerLoginServer": {
    "value": "$DOCKER_REGISTRY"
  }, 
  "dockerUserName": {
    "value": "$SPN_APPID"
  }, 
  "dockerPassword": {
    "value": "$SERVICE_PRINCIPAL_SECRET"
  },
  "dockerRegistry": {
    "value": "$DOCKER_REGISTRY"
  },
  "internalSshPublicKey": {
    "value": "$INTERNAL_SSH_PUBLIC_KEY"
  },
  "internalSshPrivateKey": {
    "value": "$INTERNAL_SSH_PRIVATE_KEY"
  },
  "baseUri": {
    "value": "$BASE_DEPLOYMENT_URI"
  },
  "k8sTemplateLink": {
    "value": "$ACS_TEMPLATE_URI"
  }, 
  "k8sParametersLink": {
    "value": "$ACS_PARAMETERS_URI"
  },
  "k8sNameSuffix": {
    "value": "$NOW"
  },
  "pachydermAddress": {
    "value": "$K8S_MASTER_IP_START:30650"
  }
}
EOF

# Create the resource group and give our service principal access
azure group create --name "$RESOURCE_GROUP" --location "$REGION"
azure role assignment create --objectId "$SPN_OBJECTID" --roleName "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP"

# Give the service principal access to the Azure Container Registry (ACR)
ACR_ROLE_EXISTS=`azure role assignment list --objectId "$SPN_OBJECTID" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$ACR_RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME" --json | jq 'length'`
if [[ ! $ACR_ROLE_EXISTS ]]; then
    azure role assignment create --objectId "$SPN_OBJECTID" --roleName "Contributor" --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$ACR_RESOURCE_GROUP/providers/Microsoft.ContainerRegistry/registries/$ACR_NAME"
fi

# Invoke the ARM
azure group deployment create --name="aurora" --resource-group="$RESOURCE_GROUP" --template-file="$SCRIPT_DIR/orchestrator.json" --parameters-file="$BASE_OUT_DIR/orchestrator.parameters.json"
