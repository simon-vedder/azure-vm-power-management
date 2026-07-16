/*
  azure-vm-power-management — tag-driven Azure VM start/stop

  Deploys the hourly runbook (../runbook/VM-PowerManagement.ps1) on an Automation
  Account with a System-Assigned identity and a least-privilege custom role. VMs opt
  in via the AutoShutdown tag; the runbook decides start vs stop per VM from the tag
  and the current hour. See ../README.md for the tag schema.
*/

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_automation_account" "main" {
  name                = var.automation_account_name
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }
}

# Tag-driven runbook (V2). Decides start/stop per VM — no action parameter.
resource "azurerm_automation_runbook" "vm_power_management" {
  name                    = "VM-PowerManagement"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell72"

  content = file("${path.module}/../runbook/VM-PowerManagement.ps1")
}

# Single HOURLY schedule — the runbook self-determines start vs stop from tags.
# (Replaces the old fixed start/stop schedules; V2 is hour-of-day driven per VM.)
resource "azurerm_automation_schedule" "hourly" {
  name                    = "vm-power-hourly"
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  frequency               = "Hour"
  interval                = 1
  description             = "Runs the tag-driven VM power management runbook every hour"
}

resource "azurerm_automation_job_schedule" "hourly" {
  resource_group_name     = azurerm_resource_group.main.name
  automation_account_name = azurerm_automation_account.main.name
  schedule_name           = azurerm_automation_schedule.hourly.name
  runbook_name            = azurerm_automation_runbook.vm_power_management.name
}

# Least-privilege custom role — exactly what the runbook needs: read + start + deallocate.
resource "azurerm_role_definition" "vm_power_manager" {
  name        = "VM Power Manager"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Least-privilege role for tag-driven VM start/stop"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/deallocate/action",
    ]
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

# Assign to the Automation Account identity at subscription scope.
# Multi-subscription: the runbook loops all subscriptions it can see — assign this
# role to the identity at each target subscription (or a management group) instead.
resource "azurerm_role_assignment" "automation_vm_power" {
  scope              = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_id = azurerm_role_definition.vm_power_manager.role_definition_resource_id
  principal_id       = azurerm_automation_account.main.identity[0].principal_id
}
