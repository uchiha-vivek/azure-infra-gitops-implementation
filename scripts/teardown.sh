#!/usr/bin/env bash
# Deletes everything this project created in Azure so nothing keeps billing:
#   - rg-gitops-dev, rg-gitops-prod (resources + policy assignments inside them)
#   - rg-gitops-tfstate (Terraform state storage)
#   - the Entra app registration and its role assignments
#
# Usage: ./scripts/teardown.sh
set -uo pipefail

APP_NAME="${APP_NAME:-sp-gitops-github-actions}"
RESOURCE_GROUPS=(rg-gitops-dev rg-gitops-prod rg-gitops-tfstate)

echo "Subscription: $(az account show --query 'name' -o tsv) ($(az account show --query 'id' -o tsv))"
echo "This will PERMANENTLY delete:"
for rg in "${RESOURCE_GROUPS[@]}"; do echo "  - resource group $rg"; done
echo "  - Entra app registration $APP_NAME"
echo
read -r -p "Type 'delete' to continue: " answer
if [ "$answer" != "delete" ]; then
  echo "Aborted."
  exit 1
fi

# 1. Resource groups (deleting a group deletes everything inside it)
for rg in "${RESOURCE_GROUPS[@]}"; do
  if [ "$(az group exists --name "$rg")" = "true" ]; then
    echo "Deleting $rg ..."
    az group delete --name "$rg" --yes --no-wait
  else
    echo "$rg not found, skipping."
  fi
done

# 2. Role assignments and the Entra app (GitHub OIDC credentials go with the app)
CLIENT_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [ -n "$CLIENT_ID" ]; then
  SP_OBJECT_ID="$(az ad sp show --id "$CLIENT_ID" --query id -o tsv 2>/dev/null || true)"
  if [ -n "$SP_OBJECT_ID" ]; then
    echo "Removing role assignments ..."
    az role assignment list --assignee "$SP_OBJECT_ID" --all --query '[].id' -o tsv |
      while read -r id; do
        az role assignment delete --ids "$id"
      done
  fi
  echo "Deleting Entra app $APP_NAME ..."
  az ad app delete --id "$CLIENT_ID"
else
  echo "Entra app $APP_NAME not found, skipping."
fi

echo
echo "Done. Resource group deletion continues in the background (a few minutes)."
echo "Check with: az group list --query \"[?starts_with(name,'rg-gitops')].name\" -o tsv"