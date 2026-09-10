# New-VmPowerSchedule

> Build a schedule from parameters instead of writing the JSON by hand

JSON is what a schedule is stored as, the way ARM JSON is what Bicep is stored as. This is the
door you author through: friendly parameters in, a validated schedule out, and a clear error
rather than a schedule that misbehaves at half past six.

The object it returns is the long form - a list of actions, each with one action type, because
that is how Microsoft.ComputeSchedule models one. Pipe it to Set-VmPowerSchedule to store it, or
to Show-VmPowerScheduleCalendar to see what it will actually do before anything else sees it.

## Syntax

```powershell
New-VmPowerSchedule [-Name] <string> -TimeZone <string> -Weekdays <string> [-ExceptDate <string[]>] [-MinimumDwellMinutes <int>] [-DisplayName <string>] [<CommonParameters>]

New-VmPowerSchedule [-Name] <string> -TimeZone <string> -Daily <string> [-ExceptDate <string[]>] [-MinimumDwellMinutes <int>] [-DisplayName <string>] [<CommonParameters>]

New-VmPowerSchedule [-Name] <string> -TimeZone <string> -Start <string> [-Days <string[]>] [-Stop <string>] [-ExceptDate <string[]>] [-MinimumDwellMinutes <int>] [-DisplayName <string>] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: None. This command builds an object and touches nothing.

Prerequisites: PowerShell 7.2 or later.

Writes: Nothing. Storing the result is Set-VmPowerSchedule's job.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Name` | String | yes | no |  | Catalogue name, and the value machines carry in their PowerSchedule tag. Lowercase letters, digits and hyphens, 3 to 40 characters, because it is also an allowedValues entry in the generated policy. |
| `-TimeZone` | String | yes | no |  | Windows form ('W. Europe Standard Time') or IANA form ('Europe/Zurich'). Both resolve on the Linux workers that run PowerShell 7.2 in Azure Automation. |
| `-Weekdays` | String | yes | no |  | Shorthand for Monday to Friday, as 'HH:mm-HH:mm'. Compiles into a Start and a Deallocate. |
| `-Daily` | String | yes | no |  | The same shorthand, every day of the week. |
| `-Days` | String[] | no | no |  | Days the explicit form applies to. Defaults to every day. |
| `-Start` | String | yes | no |  | Time to start the machines, in the explicit form. |
| `-Stop` | String | no | no |  | Time to deallocate them. Omit for a schedule that starts machines and never stops them. |
| `-ExceptDate` | String[] | no | no |  | Dates to skip, as yyyy-MM-dd. No holiday calendar ships with this tool: Switzerland alone has cantonal holidays, and a calendar that looks authoritative and is wrong is worse than none. |
| `-MinimumDwellMinutes` | Int32 | no | no | 30 | Leave a machine alone for this long after acting on it. Azure bills a five-minute minimum per start, so a schedule that flaps costs money as well as being wrong. |
| `-DisplayName` | String | no | no |  | Human label for the workbook. Defaults to the name. |

## Examples

### Example 1

```powershell
# The common case, in one line
New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30'
```

### Example 2

```powershell
# Explicit days, and a Friday that ends earlier is a second schedule rather than a special case
New-VmPowerSchedule -Name build-agents -TimeZone 'UTC' -Days Monday, Tuesday, Wednesday, Thursday -Start 06:00 -Stop 22:00
```

### Example 3

```powershell
# Managed but never stopped: better than leaving a machine untagged, because untagged is
# indistinguishable from forgotten
New-VmPowerSchedule -Name always-on -TimeZone 'Europe/Zurich' -Start 06:00
```

### Example 4

```powershell
# See what it does before storing it
New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' -ExceptDate 2026-12-24, 2026-12-25 |
    Show-VmPowerScheduleCalendar -Days 14
```

## Output

- AzureVMPowerManagement.VmPowerSchedule

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
