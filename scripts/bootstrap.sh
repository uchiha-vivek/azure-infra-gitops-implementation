#!/usr/bin/env bash
# One-time setup, run by a human with Owner (or Contributor + User Access
# Administrator) on the subscription. Creates everything Terraform and GitHub
# Actions need BEFORE the pipeline can run:
#
#   1. Resource group + storage account + container for Terraform remote state
#   2. Entra ID app registration + service principal
#   3. Federated credentials so GitHub Actions can log in via OIDC (no secrets)
#   4. Role assignments for that service principal
#
# Usage:
#   az login
#   GITHUB_ORG=<your-github-user-or-org> scripts/bootstrap.sh
#
# Safe to re-run: existing resources are reused.
set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:?Set GITHUB_ORG to your GitHub user or organisation}"
GITHUB_REPO="${GITHUB_REPO:-azure-infra-gitops}"
LOCATION="${LOCATION:-eastus}"
APP_NAME="${APP_NAME:-sp-gitops-github-actions}"
STATE_RG="rg-gitops-tfstate" # must match terraform/backend.tf
STATE_CONTAINER="tfstate"    # must match terraform/backend.tf

SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
TENANT_ID="$(az account show --query tenantId -o tsv)"

# Deterministic, globally-unique storage account name (3-24 lowercase alphanumerics).
HASH="$(printf '%s' "$SUBSCRIPTION_ID" | openssl dgst -sha1 | awk '{print $NF}' | cut -c1-8)"
STATE_SA="${STATE_SA:-stgitopstf${HASH}}"

echo "Subscription : $SUBSCRIPTION_ID"
echo "Tenant       : $TENANT_ID"
echo "State account: $STATE_SA"
echo

echo "==> Registering resource providers"
for ns in Microsoft.Storage Microsoft.Network Microsoft.Authorization; do
  az provider register --namespace "$ns" --wait >/dev/null
done

# ---------------------------------------------------------------------------
# 1. Terraform state storage
# ---------------------------------------------------------------------------
echo "==> Creating state resource group and storage account"
az group create --name "$STATE_RG" --location "$LOCATION" -o none

if ! az storage account show --name "$STATE_SA" --resource-group "$STATE_RG" -o none 2>/dev/null; then
  az storage account create \
    --name "$STATE_SA" \
    --resource-group "$STATE_RG" \
    --location "$LOCATION" \
    --sku Standard_LRS \
    --kind StorageV2 \
    --min-tls-version TLS1_2 \
    --https-only true \
    --allow-blob-public-access false \
    --allow-shared-key-access false \
    -o none
fi

# Keep history of state files so a bad apply can be recovered.
az storage account blob-service-properties update \
  --account-name "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --enable-versioning true \
  --enable-delete-retention true --delete-retention-days 14 \
  --enable-container-delete-retention true --container-delete-retention-days 14 \
  -o none

# Management-plane call, so no data-plane role is needed to create the container.
az storage container-rm create \
  --storage-account "$STATE_SA" \
  --resource-group "$STATE_RG" \
  --name "$STATE_CONTAINER" \
  -o none

STATE_SA_ID="$(az storage account show --name "$STATE_SA" --resource-group "$STATE_RG" --query id -o tsv)"

# ---------------------------------------------------------------------------
# 2. Entra ID app registration + service principal
# ---------------------------------------------------------------------------
echo "==> Creating Entra ID app registration"
CLIENT_ID="$(az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)"
if [ -z "$CLIENT_ID" ]; then
  CLIENT_ID="$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)"
fi

SP_OBJECT_ID="$(az ad sp show --id "$CLIENT_ID" --query id -o tsv 2>/dev/null || true)"
if [ -z "$SP_OBJECT_ID" ]; then
  SP_OBJECT_ID="$(az ad sp create --id "$CLIENT_ID" --query id -o tsv)"
  echo "    waiting for the service principal to replicate..."
  sleep 30
fi

# ---------------------------------------------------------------------------
# 3. Federated credentials (GitHub OIDC)
# ---------------------------------------------------------------------------
add_federated_credential() {
  local name="$1" subject="$2"
  local existing
  existing="$(az ad app federated-credential list --id "$CLIENT_ID" \
    --query "[?name=='${name}'] | length(@)" -o tsv)"
  if [ "$existing" != "0" ]; then
    echo "    $name already exists"
    return
  fi
  local tmp
  tmp="$(mktemp)"
  cat >"$tmp" <<JSON
{
  "name": "${name}",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "${subject}",
  "audiences": ["api://AzureADTokenExchange"]
}
JSON
  az ad app federated-credential create --id "$CLIENT_ID" --parameters "@${tmp}" -o none
  rm -f "$tmp"
  echo "    created $name -> $subject"
}

echo "==> Creating federated credentials"
REPO="repo:${GITHUB_ORG}/${GITHUB_REPO}"
add_federated_credential "github-pull-request" "${REPO}:pull_request"       # PR plans
add_federated_credential "github-main-branch"  "${REPO}:ref:refs/heads/main" # drift detection, prod plan
add_federated_credential "github-env-dev"      "${REPO}:environment:dev"    # dev apply
add_federated_credential "github-env-prod"     "${REPO}:environment:prod"   # prod apply (after approval)

# ---------------------------------------------------------------------------
# 4. Role assignments
# ---------------------------------------------------------------------------
assign_role() {
  local assignee="$1" principal_type="$2" role="$3" scope="$4"
  local count
  count="$(az role assignment list --assignee "$assignee" --role "$role" --scope "$scope" \
    --query 'length(@)' -o tsv)"
  if [ "$count" != "0" ]; then
    echo "    $role already assigned"
    return
  fi
  for attempt in 1 2 3 4 5; do
    if az role assignment create \
      --assignee-object-id "$assignee" \
      --assignee-principal-type "$principal_type" \
      --role "$role" --scope "$scope" -o none 2>/dev/null; then
      echo "    assigned $role"
      return
    fi
    echo "    retrying role assignment ($attempt/5)..."
    sleep 10
  done
  echo "Failed to assign $role" >&2
  exit 1
}

echo "==> Assigning roles to the service principal"
SUB_SCOPE="/subscriptions/${SUBSCRIPTION_ID}"
assign_role "$SP_OBJECT_ID" ServicePrincipal "Contributor"                   "$SUB_SCOPE"
assign_role "$SP_OBJECT_ID" ServicePrincipal "Resource Policy Contributor"   "$SUB_SCOPE"
assign_role "$SP_OBJECT_ID" ServicePrincipal "Storage Blob Data Contributor" "$STATE_SA_ID"

# So you can also run terraform locally against the same remote state.
ME_OBJECT_ID="$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)"
if [ -n "$ME_OBJECT_ID" ]; then
  assign_role "$ME_OBJECT_ID" User "Storage Blob Data Contributor" "$STATE_SA_ID"
fi

# ---------------------------------------------------------------------------
# Done: print what to configure in GitHub
# ---------------------------------------------------------------------------
cat <<EOF2

================ Bootstrap complete ================

Set these GitHub repository VARIABLES (none of them are secrets):

  gh variable set AZURE_CLIENT_ID          --body "${CLIENT_ID}"       --repo ${GITHUB_ORG}/${GITHUB_REPO}
  gh variable set AZURE_TENANT_ID          --body "${TENANT_ID}"       --repo ${GITHUB_ORG}/${GITHUB_REPO}
  gh variable set AZURE_SUBSCRIPTION_ID    --body "${SUBSCRIPTION_ID}" --repo ${GITHUB_ORG}/${GITHUB_REPO}
  gh variable set TFSTATE_STORAGE_ACCOUNT  --body "${STATE_SA}"        --repo ${GITHUB_ORG}/${GITHUB_REPO}

For local terraform runs:

  export ARM_SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
  terraform -chdir=terraform init \\
    -backend-config="storage_account_name=${STATE_SA}" \\
    -backend-config="key=dev.tfstate"
EOF2