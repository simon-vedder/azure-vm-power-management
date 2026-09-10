# Remove-VmPowerSchedule

> Take a schedule out of the custom catalogue

Removes from PM_ScheduleCatalogCustom only. A schedule that came from the deployment cannot be
removed here, because the deployment would put it back on the next run and the removal would
look like it had failed. Removing an override reveals the deployment's version again rather
than deleting anything.

Machines still tagged with a name that no longer resolves are not left in limbo: they are
reported as ScheduleNotInCatalogue on the next plan, which is a decision to do nothing with a
reason attached, not a silent one. This command names them before it removes anything.

## Syntax

```powershell
Remove-VmPowerSchedule [-Name] <string[]> -ResourceGroupName <string> -AutomationAccountName <string> [-SubscriptionId <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: Microsoft.Automation/automationAccounts/variables/write and /read on the
Automation Account.

Prerequisites: PowerShell 7.2 or later and Az.Accounts.

Writes: The Automation variable PM_ScheduleCatalogCustom.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Name` | String[] | yes | yes |  | Schedules to remove. |
| `-ResourceGroupName` | String | yes | no |  | Resource group holding the Automation Account. |
| `-AutomationAccountName` | String | yes | no |  | The Automation Account. |
| `-SubscriptionId` | String | no | no |  | Subscription holding the account. Defaults to the current context. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
# Drop an override and let the shipped example apply again
Remove-VmPowerSchedule -Name office-hours-ch -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower
```

### Example 2

```powershell
# See what would happen first
Remove-VmPowerSchedule -Name night-shift -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower -WhatIf
```

## Output

- None

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
