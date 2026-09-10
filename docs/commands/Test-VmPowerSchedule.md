# Test-VmPowerSchedule

> Check a schedule or a whole catalogue, and report what is wrong rather than throwing

Every path into the catalogue goes through this, which is why it reports instead of failing at
the first problem: somebody validating twelve schedules wants all twelve answers, not the first
one. Set-VmPowerSchedule calls it and refuses to store anything that does not pass.

It also checks the things a schema cannot: two schedules with the same name, and a catalogue
whose names would not survive being turned into the allowedValues of a policy.

Pass -Detailed to get the expanded schedule back alongside the verdict, which is what
Show-VmPowerScheduleCalendar consumes.

## Syntax

```powershell
Test-VmPowerSchedule [-Schedule] <Object[]> [-Detailed] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: None. This command reads objects in memory.

Prerequisites: PowerShell 7.2 or later.

Writes: Nothing.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Schedule` | Object[] | yes | yes |  | One schedule or a catalogue of them, in either the shorthand or the long form. |
| `-Detailed` | SwitchParameter | no | no |  | Include the expanded schedule on each result. |

## Examples

### Example 1

```powershell
# Validate a catalogue read out of a file before it goes anywhere near a deployment
Get-Content ./catalog.json -Raw | ConvertFrom-Json | Test-VmPowerSchedule | Format-Table Name, Valid, Problem
```

### Example 2

```powershell
# The one-liner before storing
New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' | Test-VmPowerSchedule
```

## Output

- AzureVMPowerManagement.VmPowerScheduleValidation

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
