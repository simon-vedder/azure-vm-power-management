variable "subscription_id" {
  description = "Subscription to deploy the automation account into"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "rg-vm-automation"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "West Europe"
}

variable "automation_account_name" {
  description = "Name of the automation account"
  type        = string
  default     = "aa-vm-power-management"
}
