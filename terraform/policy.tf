# Azure Policy guardrails, assigned at resource group scope.
# These use built-in policy definitions, so there is nothing to author.
# Policy changes can take up to ~30 minutes to start enforcing after assignment.

locals {
  policy_definition_prefix = "/providers/Microsoft.Authorization/policyDefinitions"
}

# Resources may only be created in approved regions.
resource "azurerm_resource_group_policy_assignment" "allowed_locations" {
  name                 = "allowed-locations"
  display_name         = "Allowed locations"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "${local.policy_definition_prefix}/e56962a6-4747-49cd-b67b-bf8b01975c4c"

  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })
}

# Storage accounts must require HTTPS.
resource "azurerm_resource_group_policy_assignment" "storage_secure_transfer" {
  name                 = "storage-secure-transfer"
  display_name         = "Secure transfer to storage accounts should be enabled"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "${local.policy_definition_prefix}/404c3081-a854-4457-ae30-26a93ef643f9"

  parameters = jsonencode({
    effect = { value = "Deny" }
  })
}

# Storage accounts must not allow public blob access.
resource "azurerm_resource_group_policy_assignment" "storage_no_public_access" {
  name                 = "storage-no-public-access"
  display_name         = "Storage account public access should be disallowed"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "${local.policy_definition_prefix}/4fa4b6c0-31ca-4c0d-b10d-24b96f62a751"

  parameters = jsonencode({
    effect = { value = "Deny" }
  })
}

# Every resource must carry an "environment" tag.
resource "azurerm_resource_group_policy_assignment" "require_environment_tag" {
  name                 = "require-environment-tag"
  display_name         = "Require an environment tag on resources"
  resource_group_id    = azurerm_resource_group.main.id
  policy_definition_id = "${local.policy_definition_prefix}/871b6d14-10aa-478d-b590-94f262ecfa99"

  parameters = jsonencode({
    tagName = { value = "environment" }
  })
}