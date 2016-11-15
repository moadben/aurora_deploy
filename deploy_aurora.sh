#! /bin/bash

# Shared config information
BASENAME=$1
RESOURCE_GROUP=$2
REGION=$3
ADMIN_NAME=$4
SSH_KEYFILE=$5
SERVICE_PRINCIPAL_ID=$6
SERVICE_PRINCIPAL_SECRET=$7
DEPLOYMENT_STORAGE_BASEURI=$8
DEPLOYMENT_STORAGE_SAS=$9
DOCKER_HUB_USERNAME=$10
DOCKER_HUB_PASSWORD=$11
K8S_AGENT_COUNT=${12:-4}
K8S_AGENT_VM_SIZE=${13:-'Standard_D2_v2'}
GLUSTER_NODE_COUNT=${14:-4}
GLUSTER_NODE_VM_SIZE=${15:-'Standard_D1_v2'}
ACS_ENGINE_CONFIG_FILE=$16
BASE_DEPLOYMENT_URI=${17:-'https://raw.githubusercontent.com/jpoon/aurora_deploy/master/'}

NOW=`date +"%s"`

SUBSCRIPTION_ID=`azure account list --json | jq -r '.[0].id'`
# Statically assign IP addresses to master node(s)
K8S_MASTER_IP_START="10.0.1.100"
# Statically assign IP address to LB (so we can specify it to the Ingress apps)
PACHYDERM_ENDPOINT="10.0.1.250"

BASE_OUT_DIR="/tmp/deploy_aurora"
mkdir $BASE_OUT_DIR
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
K8S_DEPLOYMENT_FILE="$BASE_OUT_DIR/kube-acsengine-$NOW.json"
ACS_ENGINE_OUTPUT_DIR="$BASE_OUT_DIR/output/kube-config-$NOW"

SSH_KEY=`cat $SSH_KEYFILE`
# Generate keypair for internal VM communication
INTERNAL_KEY_FILE=$BASE_OUT_DIR/id_rsa-$NOW
ssh-keygen -f $INTERNAL_KEY_FILE -N ""
INTERNAL_SSH_PRIVATE_KEY=`cat $INTERNAL_KEY_FILE | sed '$d' | sed '1d' | tr -d '\n'`
INTERNAL_SSH_PUBLIC_KEY=`cat $INTERNAL_KEY_FILE.pub | tr -d '\n'`

echo "Generating acs-engine config."
if [[ ! $ACS_ENGINE_CONFIG_FILE ]]; then
    ACS_ENGINE_CONFIG_FILE=$SCRIPT_DIR/k8s/config/kubernetesvnet.json
fi
cat $ACS_ENGINE_CONFIG_FILE \
    | sed "s/@@RESOURCE_GROUP@@/$RESOURCE_GROUP/g" \
    | sed "s/@@DNS_PREFIX@@/$BASENAME/g" \
    | sed "s/@@SUBSCRIPTION_ID@@/$SUBSCRIPTION_ID/g" \
    | sed "s/@@AGENT_COUNT@@/$K8S_AGENT_COUNT/g" \
    | sed "s/@@AGENT_VM_SIZE@@/$K8S_AGENT_VM_SIZE/g" \
    | sed "s/@@VNET_NAME@@/$BASENAME-vnet/g" \
    | sed "s/@@KUBERNETES_SUBNET@@/kubernetes/g" \
    | sed "s/@@K8S_MASTER_IP_START@@/$K8S_MASTER_IP_START/g" \
    | sed "s/@@ADMIN_NAME@@/$ADMIN_NAME/g" \
    | sed "s/@@SERVICE_PRINCIPAL_ID@@/$SERVICE_PRINCIPAL_ID/g" \
    | sed "s/@@SERVICE_PRINCIPAL_SECRET@@/$SERVICE_PRINCIPAL_SECRET/g" \
    | sed "s~@@SSH_KEY@@~$INTERNAL_SSH_PUBLIC_KEY~g" \
    | tee $K8S_DEPLOYMENT_FILE

echo "Executing acs-engine to generate K8s config"
"$SCRIPT_DIR/k8s/bin/acs-engine" -artifacts $ACS_ENGINE_OUTPUT_DIR $K8S_DEPLOYMENT_FILE

echo "Moving ACS K8S deployment assets to storage account"
# Parameter Link files need a slightly different format
cat << EOF > $ACS_ENGINE_OUTPUT_DIR/acs-azuredeploy.parameters.json 
{
  "\$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": $(cat $ACS_ENGINE_OUTPUT_DIR/azuredeploy.parameters.json)
}
EOF

if [[ $DEPLOYMENT_STORAGE_SAS && ${DEPLOYMENT_STORAGE_SAS:0:1} != '?' ]]; then
    DEPLOYMENT_STORAGE_SAS="?$DEPLOYMENT_STORAGE_SAS"
fi
DEPLOYMENT_STORAGE_BASEURI="${DEPLOYMENT_STORAGE_BASEURI%%+(/)}"
ACS_TEMPLATE_URI="$DEPLOYMENT_STORAGE_BASEURI/azuredeploy-$NOW.json$DEPLOYMENT_STORAGE_SAS"
ACS_PARAMETERS_URI="$DEPLOYMENT_STORAGE_BASEURI/azuredeploy-$NOW.parameters.json$DEPLOYMENT_STORAGE_SAS"

curl -X PUT -d @"$ACS_ENGINE_OUTPUT_DIR/azuredeploy.json" -H "date:$(date -u +%a,\ %d\ %b\ %Y\ %H:%M:%S\ GMT)" -H "x-ms-blob-type:BlockBlob" -H "x-ms-version:2012-02-12" $ACS_TEMPLATE_URI
curl -X PUT -d @"$ACS_ENGINE_OUTPUT_DIR/acs-azuredeploy.parameters.json" -H "date:$(date -u +%a,\ %d\ %b\ %Y\ %H:%M:%S\ GMT)" -H "x-ms-blob-type:BlockBlob" -H "x-ms-version:2012-02-12" $ACS_PARAMETERS_URI

echo "Invoking ARM E2E template"
# Generate parameters file
cat << EOF > $BASE_OUT_DIR/orchestrator.parameters.json
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
  "dockerHubUsername": {
    "value": "$DOCKER_HUB_USERNAME"
  }, 
  "dockerHubPassword": {
    "value": "$DOCKER_HUB_PASSWORD"
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
  "pachydermAddress": {
    "value": "$PACHYDERM_ENDPOINT:650"
  }
}
EOF
# Now invoke ARM
azure group create --name "$RESOURCE_GROUP" --location "$REGION"
azure group deployment create --name="aurora" --resource-group="$RESOURCE_GROUP" --template-file="$SCRIPT_DIR/orchestrator.json" --parameters-file="$BASE_OUT_DIR/orchestrator.parameters.json"
