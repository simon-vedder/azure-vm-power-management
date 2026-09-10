# Set-VmPowerSchedule

> Store a schedule in the catalogue, without a redeployment

Writes into PM_ScheduleCatalogCustom, which the deployment never touches. That split is the
whole reason there are two variables: one owned by infrastructure as code, one owned by whoever
is on the end of a phone at half past five - see docs/decisions/0005.

A schedule with a name that already exists in the custom catalogue replaces it. A name that
exists only in the deployment catalogue is shadowed rather than changed, so the shipped example
stays intact and a later redeployment does not fight the override.

Everything is validated before anything is written, and the write is one replacement of the
whole variable rather than an append, so a half-written catalogue is not a state this can leave
behind.

## Syntax

```powershell
Set-VmPowerSchedule [-Schedule] <Object[]> [-ResourceGroupName] <string> [-AutomationAccountName] <string> [[-SubscriptionId] <string>] [-PassThru] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: Microsoft.Automation/automationAccounts/variables/write and /read on the
Automation Account. Automation Contributor covers it; a custom role limited to those two actions
is narrower and is what a person authoring schedules should have.

Prerequisites: PowerShell 7.2 or later and Az.Accounts.

Writes: The Automation variable PM_ScheduleCatalogCustom. It never writes PM_ScheduleCatalog,
which belongs to the deployment.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Schedule` | Object[] | yes | yes |  | Schedules to store, from New-VmPowerSchedule or read back from a file. |
| `-ResourceGroupName` | String | yes | no |  | Resource group holding the Automation Account. |
| `-AutomationAccountName` | String | yes | no |  | The Automation Account. |
| `-SubscriptionId` | String | no | no |  | Subscription holding the account. Defaults to the current context. |
| `-PassThru` | SwitchParameter | no | no |  | Return the stored schedules. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
# The one-liner this whole design exists for
New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' |
    Set-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower
```

### Example 2

```powershell
# Look before you store
$s = New-VmPowerSchedule -Name night-shift -TimeZone 'Europe/Zurich' -Daily '22:00-06:00'
$s | Show-VmPowerScheduleCalendar -Days 3
$s | Set-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower
```

## Output

- AzureVMPowerManagement.VmPowerSchedule when -PassThru is given, otherwise nothing

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
