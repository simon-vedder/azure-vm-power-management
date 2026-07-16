/*
  OPTIONAL example VM — demonstrates the AutoShutdown tag schema so you can see the
  runbook act on something. Delete this file for a runbook-only deployment.

  Deliberately no public IP / no open RDP — an internet-facing management port would
  fail a network-exposure audit. Reach the VM over Bastion or a private path.
  Provide example_vm_admin_password via a tfvars file or Key Vault — never commit it.
*/

variable "example_vm_admin_password" {
  description = "Admin password for the example VM"
  type        = string
  sensitive   = true
}

resource "azurerm_virtual_network" "example" {
  name                = "vnet-vm-management"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "example" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.0.2.0/24"]
}

resource "azurerm_network_interface" "example" {
  name                = "nic-vm-management"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.example.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "example" {
  name                = "vm-management"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2ms"
  admin_username      = "azureuser"
  admin_password      = var.example_vm_admin_password

  network_interface_ids = [azurerm_network_interface.example.id]

  # Attaches the self-service identity so the PowerMate GUI can run on this VM.
  # Remove this block (and gui.tf) for a runbook-only deployment.
  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.gui.id]
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  # This is what opts the VM into power management. Without the AutoShutdown tag the
  # runbook ignores the VM entirely.
  tags = {
    AutoShutdown             = "8-18" # start at 08:00, stop at 18:00
    AutoShutdown-TimeZone    = "W. Europe Standard Time"
    AutoShutdown-ExcludeDays = "Saturday,Sunday"
  }
}
