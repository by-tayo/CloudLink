#!/usr/bin/env bash
# Deploys logic-app/workflow.json into the Logic App resource that Terraform
# provisioned. Terraform's azurerm_logic_app_workflow resource creates the
# empty workflow container; encoding every trigger/action as HCL resources is
# more brittle than maintaining one workflow JSON file, so this script pushes
# the definition directly via the Azure CLI.
#
# Usage: ./deploy-workflow.sh <resource-group> <logic-app-name>
set -euo pipefail

RESOURCE_GROUP="${1:?Usage: $0 <resource-group> <logic-app-name>}"
LOGIC_APP_NAME="${2:?Usage: $0 <resource-group> <logic-app-name>}"
WORKFLOW_FILE="$(dirname "$0")/../logic-app/workflow.json"

echo "Deploying ${WORKFLOW_FILE} to Logic App '${LOGIC_APP_NAME}' in '${RESOURCE_GROUP}'..."

az logic workflow update \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${LOGIC_APP_NAME}" \
  --definition "@${WORKFLOW_FILE}"

echo "Done. Trigger URL:"
az logic workflow show \
  --resource-group "${RESOURCE_GROUP}" \
  --name "${LOGIC_APP_NAME}" \
  --query "accessEndpoint" -o tsv
