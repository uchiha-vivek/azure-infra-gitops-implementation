#!/usr/bin/env bash
# Usage: scripts/check-drift.sh <dev|prod>
# Fails if Azure no longer matches the Terraform code (someone changed it by hand).
set -uo pipefail

ENVIRONMENT="${1:?Usage: $0 <dev|prod>}"
cd "$(dirname "$0")/../terraform"

# Exit codes from -detailed-exitcode: 0 = no changes, 1 = error, 2 = changes (drift)
terraform plan -input=false -no-color -lock=false -detailed-exitcode \
  -var-file="environments/${ENVIRONMENT}.tfvars"
code=$?

if [ "$code" -eq 0 ]; then
  echo "No drift detected in ${ENVIRONMENT}."
elif [ "$code" -eq 2 ]; then
  echo "::error::Drift detected in ${ENVIRONMENT}: Azure differs from the Terraform code."
  exit 1
else
  echo "::error::terraform plan failed for ${ENVIRONMENT}."
  exit 1
fi