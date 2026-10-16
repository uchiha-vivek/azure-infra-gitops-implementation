
terraform {
  backend "azurerm" {
    resource_group_name = "rg-gitops-tfstate"
    container_name      = "tfstate"
    use_azuread_auth    = true
  }
}