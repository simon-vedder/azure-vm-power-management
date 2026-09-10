# Get-VmPowerSchedule

> Read the schedule catalogue out of an Automation Account

The catalogue lives in two Automation variables and this merges them. PM_ScheduleCatalog is
owned and overwritten by the deployment and holds the examples that ship. PM_ScheduleCatalogCustom
is written only by Set-VmPowerSchedule and the deployment never touches it.

A custom entry wins on a name collision, so an example can be overridden without being edited
and a redeployment never eats somebody's work. Every schedule comes back with the Source it came
from, because "why did my change not take effect" is otherwise unanswerable.

Each entry is expanded and validated on the way out, so a catalogue that was edited by hand in
the portal fails here rather than halfway through a run.

## Syntax

```powershell
Get-VmPowerSchedule [-ResourceGroupName] <string> [-AutomationAccountName] <string> [[-SubscriptionId] <string>] [[-Name] <string[]>] [[-Source] <string>] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: Microsoft.Automation/automationAccounts/variables/read on the Automation
Account. Reader on the account covers it.

Prerequisites: PowerShell 7.2 or later and Az.Accounts.

Writes: Nothing.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-ResourceGroupName` | String | yes | no |  | Resource group holding the Automation Account. |
| `-AutomationAccountName` | String | yes | no |  | The Automation Account the deployment created. |
| `-SubscriptionId` | String | no | no |  | Subscription holding the account. Defaults to the current context. |
| `-Name` | String[] | no | no |  | Return only these schedules. |
| `-Source` | String | no | no |  | Read only one of the two variables, rather than the merged view. |

## Examples

### Example 1

```powershell
# The whole catalogue, and where each entry came from
Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower |
    Format-Table Name, TimeZone, Source
```

### Example 2

```powershell
# What one schedule will actually do over the next fortnight
Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower -Name office-hours-ch |
    Show-VmPowerScheduleCalendar
```

### Example 3

```powershell
# The plan for the whole estate, using the catalogue the runbook would use
$catalog = Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower
Get-VmPowerPlan -Schedule $catalog | Format-Table Name, Schedule, PowerState, Action, Reason
```

## Output

- AzureVMPowerManagement.VmPowerSchedule

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
