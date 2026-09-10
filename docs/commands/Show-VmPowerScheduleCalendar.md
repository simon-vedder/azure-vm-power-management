# Show-VmPowerScheduleCalendar

> Print the next few days of a schedule, so a mistake is something you read rather than survive

Most schedule mistakes are not syntax errors. They are "I did not think about the Sunday", or
"07:30 in which time zone", or a daylight saving change nobody pictured. A schema validator
finds none of those. A printed calendar finds all three.

It computes occurrences with the same function the decision engine uses. A preview produced by
different code from the one that runs is a preview that eventually lies.

Both daylight saving cases are visible in the Note column rather than being smoothed away: an
action that fell into the spring gap shows as shifted, and one in the doubled autumn hour shows
as ambiguous.

## Syntax

```powershell
Show-VmPowerScheduleCalendar [-Schedule] <Object[]> [[-Days] <int>] [[-FromUtc] <datetime>] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: None. This command computes times in memory.

Prerequisites: PowerShell 7.2 or later.

Writes: Nothing.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Schedule` | Object[] | yes | yes |  | One or more schedules, in either form. |
| `-Days` | Int32 | no | no | 14 | How many days ahead to render. Fourteen covers a fortnight, which is where a wrong weekday shows. |
| `-FromUtc` | DateTime | no | no | [datetime]::UtcNow | Start of the window. Defaults to now, and can be set to look at a specific date - a daylight saving weekend, for instance. |

## Examples

### Example 1

```powershell
# What will this actually do?
New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' |
    Show-VmPowerScheduleCalendar
```

### Example 2

```powershell
# Look straight at the daylight saving weekend rather than waiting for it
$s | Show-VmPowerScheduleCalendar -FromUtc ([datetime]'2026-03-28T00:00:00Z') -Days 3
```

### Example 3

```powershell
# Everything in the catalogue, one table
Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower |
    Show-VmPowerScheduleCalendar -Days 7 | Format-Table Schedule, DayOfWeek, LocalTime, Action, Note
```

## Output

- AzureVMPowerManagement.VmPowerOccurrence

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
