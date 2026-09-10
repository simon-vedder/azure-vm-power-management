# Invoke-AzureVMPowerManagementRunbook.ps1

> Run AzureVMPowerManagement from an Azure Automation runbook

Thin wrapper around the AzureVMPowerManagement module: signs in with the Automation Account's managed
identity, plans the work through the module and either reports it or performs it. The runbook knows
the operation; the module knows the rules. Keep this file free of rules.

It ships disarmed. -Armed defaults to false, so a deployed schedule discovers, decides and prints
everything while changing nothing. Read a week of that before arming it - see
docs/decisions/0004-eager-to-start-reluctant-to-stop.md.

Discovery reaches every subscription the managed identity can read in one Resource Graph call, so
-SubscriptionId is a narrowing option rather than a requirement. All optional flags are [bool]
instead of [switch] because the Automation "Start runbook" dialog cannot populate switch parameters.

## Syntax

```powershell
./Invoke-AzureVMPowerManagementRunbook.ps1 [[-SubscriptionId] <string[]>] [[-Armed] <bool>] [-MaximumActions] <int> [[-MinimumDwellMinutes] <int>] [[-IncludeUntagged] <bool>] [[-ScheduleTag] <string>] [[-ExclusionTag] <string>] [[-ManagedIdentityClientId] <string>] [<CommonParameters>]
```

## Requirements and notes

Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
RequiredPermissions: Managed identity with Reader for discovery, plus the custom role from
                     deploy/main.bicep for the power actions, on the target scope.
Prerequisites:       Azure Automation PowerShell 7.2+ runtime; modules AzureVMPowerManagement,
                     Az.Accounts and Az.Compute.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-SubscriptionId` | String[] | no | no |  | Narrow discovery to these subscriptions. Leave empty to plan across everything the identity reads. |
| `-Armed` | Boolean | no | no |  | False, the default, plans and reports without touching a machine. True performs the plan. |
| `-MaximumActions` | Int32 | yes | no | 0 | Refuse the whole run if it would act on more machines than this. There is no safe default for somebody else's estate, so the deployment sets it explicitly. |
| `-MinimumDwellMinutes` | Int32 | no | no | 30 | Leave a machine alone if this runbook acted on it more recently than this. |
| `-IncludeUntagged` | Boolean | no | no |  | Also act on machines carrying no schedule tag. Off by default: opt-in is the rule. Untagged machines that are powered off and still billed are reported either way. |
| `-ScheduleTag` | String | no | no |  | Tag key that opts a machine in. Empty uses the module's default, PowerSchedule. |
| `-ExclusionTag` | String | no | no |  | Tag key that protects a machine from every rule. Empty uses the module's default. |
| `-ManagedIdentityClientId` | String | no | no |  | Client ID of a user-assigned managed identity. Leave empty for the system-assigned identity. |

## Examples

### Example 1

```powershell
# What a deployed schedule does on day one: plan the whole estate, change nothing.
.\Invoke-AzureVMPowerManagementRunbook.ps1 -MaximumActions 50
```

### Example 2

```powershell
# Armed, limited to one subscription, refusing any run that would touch more than twenty machines.
.\Invoke-AzureVMPowerManagementRunbook.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -Armed $true -MaximumActions 20
```

## Output

- AzureVMPowerManagement.VmPowerPlan when disarmed, AzureVMPowerManagement.VmPowerPlanResult when
armed, one per machine, plus a summary string.

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
