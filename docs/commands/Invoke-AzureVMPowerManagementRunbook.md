# Invoke-AzureVMPowerManagementRunbook.ps1

> Run AzureVMPowerManagement from an Azure Automation runbook

Thin wrapper around the AzureVMPowerManagement module: signs in with the Automation Account's managed
identity, selects the subscription, discovers work through the module and either reports it or
applies it. The runbook knows the operation; the module knows the logic. Keep this file free of
rules.

All optional flags are [bool] instead of [switch] because the Automation "Start runbook" dialog
cannot populate switch parameters. -DryRun maps to -WhatIf on the module. Requires the
AzureVMPowerManagement module and Az.Accounts in the Automation Account's PowerShell 7.2+ runtime.

## Syntax

```powershell
./Invoke-AzureVMPowerManagementRunbook.ps1 [-SubscriptionId] <string> [[-Mode] <string>] [[-ResourceGroupName] <string>] [[-DryRun] <bool>] [[-ManagedIdentityClientId] <string>] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
RequiredPermissions: Managed identity with the custom role from deploy/main.bicep on the target scope.
Prerequisites:       Azure Automation PowerShell 7.2+ runtime; modules AzureVMPowerManagement, Az.Accounts

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-SubscriptionId` | String | yes | no |  | The subscription to operate on. One per job. |
| `-Mode` | String | no | no | Report | Report lists findings and changes nothing. Apply removes what the findings point at. |
| `-ResourceGroupName` | String | no | no |  | Restrict discovery to one resource group. |
| `-DryRun` | Boolean | no | no |  | Apply mode only: run the module with -WhatIf. |
| `-ManagedIdentityClientId` | String | no | no |  | Client ID of a user-assigned managed identity. Leave empty for the system-assigned identity. |

## Examples

### Example 1

```powershell
' -Mode Report
```

## Output

- AzureVMPowerManagement.VmPowerPlan or AzureVMPowerManagement.VmPowerPlanRemoval, one per item, plus a summary string

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
