#!/bin/bash
NOW=`date +"%s"`

# Shared config information
DNS_PREFIX=$1
RESOURCE_GROUP=$2
ADMIN_NAME=$3
SERVICE_PRINCIPAL_ID=$4
SERVICE_PRINCIPAL_SECRET=$5
SSH_KEYFILE=$6

# Default values
# If a resource group does not already exist, use the "DEFAULT_REGION"
DEFAULT_REGION="westus2"

# VNet config information
VNET_NAME="$DNS_PREFIX""VNet"
KUBERNETES_SUBNET="$DNS_PREFIX""KubernetesSubnet"
GLUSTER_SUBNET="$DNS_PREFIX""GlusterSubnet"

# Kubernetes config information
AGENT_COUNT=4
AGENT_VM_SIZE="Standard_D2_v2"

# Gluster config information
GLUSTER_NODE_COUNT=4
GLUSTER_VM_SIZE="Standard_D1_v2"

# Retrieve account and region information
SUBSCRIPTION_ID=`azure account list --json | jq -r '.[0].id'`
# Check if resource group already present
azure group list --json | grep "\"name\": \"$RESOURCE_GROUP\"" >& /dev/null
if [ $? -eq 1 ]
then
  echo "Creating resource group"
  azure group create --name "$RESOURCE_GROUP" --location "$DEFAULT_REGION"
fi
RESOURCE_GROUP_REGION=`azure group show $RESOURCE_GROUP --json | jq -r '.location'`

SSH_KEY=`cat $SSH_KEYFILE`

SCRIPT_DIR=`dirname $( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )`
TOPLEVEL_AZURE_DEPLOY_JSON=`echo ${SCRIPT_DIR}/toplevel.azuredeploy.json`
K8S_CONFIG_FILE=`echo ${SCRIPT_DIR}/k8s/config/kubernetesvnet.json`
K8S_DEPLOYMENT_FILE=`echo ${SCRIPT_DIR}/k8s/config/kube-acsengine-$NOW.json`
DEPLOYMENT_OUTPUT_DIR=`echo ${SCRIPT_DIR}/output/deployment-$NOW`
mkdir -p $DEPLOYMENT_OUTPUT_DIR

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
K8S_AZUREDEPLOY_PARAMETERS_JSON_CONTENT=`cat $K8S_AZUREDEPLOY_PARAMETERS_JSON`
DEPLOYMENT_K8S_AZUREDEPLOY_PARAMETERS_JSON_FILE=`echo $DEPLOYMENT_OUTPUT_DIR/k8s.azuredeploy.parameters.json`

# Parameter Link files need a slightly different format
cat << EOF > $DEPLOYMENT_K8S_AZUREDEPLOY_PARAMETERS_JSON_FILE
{
  "\$schema": "http://schema.management.azure.com/schemas/2015-01-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": $K8S_AZUREDEPLOY_PARAMETERS_JSON_CONTENT
}
EOF

azure storage blob upload --json --account-name "$K8S_STORAGE_ACCOUNT_NAME" --account-key "$K8S_STORAGE_ACCOUNT_KEY" --file "$K8S_AZUREDEPLOY_JSON" --blobtype block --container "$K8S_STORAGE_ACCOUNT_CONTAINER" --blob azuredeploy.json
azure storage blob upload --json --account-name "$K8S_STORAGE_ACCOUNT_NAME" --account-key "$K8S_STORAGE_ACCOUNT_KEY" --file "$DEPLOYMENT_K8S_AZUREDEPLOY_PARAMETERS_JSON_FILE" --blobtype block --container "$K8S_STORAGE_ACCOUNT_CONTAINER" --blob azuredeploy.parameters.json

# Parameters to pass into the template
K8S_AZUREDEPLOY_JSON_LINK="https://$K8S_STORAGE_ACCOUNT_NAME.blob.core.windows.net/$K8S_STORAGE_ACCOUNT_CONTAINER/azuredeploy.json"
K8S_AZUREDEPLOY_PARAMETERS_JSON_LINK="https://$K8S_STORAGE_ACCOUNT_NAME.blob.core.windows.net/$K8S_STORAGE_ACCOUNT_CONTAINER/azuredeploy.parameters.json"

# Generate parameter file for deployment
echo "Generating deployment parameter file."
DEPLOYMENT_PARAMETERS_FILE=`echo $DEPLOYMENT_OUTPUT_DIR/azuredeploy.parameters.json`
cat << EOF > $DEPLOYMENT_PARAMETERS_FILE
{
  "dnsPrefix": {
    "value": "$DNS_PREFIX"
  },
  "virtualNetworkName": {
    "value": "$VNET_NAME"
  },
  "kubernetesSubnetName": {
    "value": "$KUBERNETES_SUBNET"
  },
  "glusterSubnetName": {
    "value": "$GLUSTER_SUBNET"
  }, 
  "kubernetesAzureDeployJsonLink": {
    "value": "$K8S_AZUREDEPLOY_JSON_LINK"
  },
  "kubernetesAzureDeployParametersJsonLink": {
    "value": "$K8S_AZUREDEPLOY_PARAMETERS_JSON_LINK"
  },
  "adminUserName": {
    "value": "$ADMIN_NAME"
  },
  "sshKeyData": {
    "value": "$SSH_KEY"
  },
  "glusterVmSize": {
    "value": "$GLUSTER_VM_SIZE"
  }, 
  "glusterNodeCount": {
    "value": $GLUSTER_NODE_COUNT
  }
}
EOF

echo "Validating deployment template"
echo "  template:    $TOPLEVEL_AZURE_DEPLOY_JSON"
echo "  parameters:  $DEPLOYMENT_PARAMETERS_FILE"
azure group template validate --resource-group="$RESOURCE_GROUP" --template-file="$TOPLEVEL_AZURE_DEPLOY_JSON" --parameters-file="$DEPLOYMENT_PARAMETERS_FILE"

echo "Deploying template"
echo "  template:    $TOPLEVEL_AZURE_DEPLOY_JSON"
echo "  parameters:  $DEPLOYMENT_PARAMETERS_FILE"
azure group deployment create --name="$RESOURCE_GROUP-dep" --resource-group="$RESOURCE_GROUP" --template-file="$TOPLEVEL_AZURE_DEPLOY_JSON" --parameters-file="$DEPLOYMENT_PARAMETERS_FILE"
