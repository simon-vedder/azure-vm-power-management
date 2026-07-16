/*
  OPTIONAL — the PowerMate GUI (../gui/PowerMate.ps1).

  Runs ON a VM and lets end-users skip today's shutdown (sets AutoShutdown-ExcludeOn)
  or deallocate the VM immediately. It needs an identity on the VM that can read/write
  the VM's tags and deallocate it. Delete this file (and the identity block in
  example-vm.tf) if you don't deploy the GUI.
*/

resource "azurerm_user_assigned_identity" "gui" {
  name                = "uami-vm-selfservice"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

# Least-privilege role for the on-VM self-service GUI (tags + deallocate).
resource "azurerm_role_definition" "vm_self_service" {
  name        = "VM Self-Service"
  scope       = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  description = "Lets the on-VM GUI read/write its own AutoShutdown tags and deallocate itself"

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/write",
      "Microsoft.Compute/virtualMachines/deallocate/action",
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/tags/read",
      "Microsoft.Resources/tags/write",
    ]
    not_actions = []
  }

  assignable_scopes = [
    "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  ]
}

resource "azurerm_role_assignment" "gui_self_service" {
  scope              = "/subscriptions/${data.azurerm_client_config.current.subscription_id}"
  role_definition_id = azurerm_role_definition.vm_self_service.role_definition_resource_id
  principal_id       = azurerm_user_assigned_identity.gui.principal_id
}
