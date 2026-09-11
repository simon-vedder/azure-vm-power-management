function ConvertTo-VmPowerStoredSchedule {
    <#
    .SYNOPSIS
    Turn an expanded schedule back into the camelCase shape the catalogue is written in.

    .DESCRIPTION
    Two things write a catalogue variable and they used to disagree about casing. The deployment
    writes camelCase, because that is the documented shape and what Bicep produces. This module
    stored the expanded object, which is PowerShell and therefore PascalCase. Every reader in the
    module is case-insensitive, so nothing complained.

    The runbook is where it mattered. Get-AutomationVariable hands a variable back as a
    Newtonsoft JObject, and a JObject indexes case-sensitively: reading 'name' finds the
    deployment's entries and returns empty for the module's. Both custom entries then keyed on an
    empty string, the second replaced the first, and a machine tagged with the lost one reported
    ScheduleNotInCatalogue - which looks exactly like a machine nobody onboarded. Measured against
    a real Automation Account on 2026-09-11.

    Tolerating the mismatch at the read side is in the runbook as well, because a catalogue stored
    by an older version is still out there. This is the other half: stop creating it.

    .PARAMETER Schedule
    An expanded schedule, as Expand-VmPowerSchedule returns it.
    #>
    [CmdletBinding()]
    [OutputType([ordered])]
    param(
        [Parameter(Mandatory)]
        $Schedule
    )

    $actions = [System.Collections.Generic.List[object]]::new()
    foreach ($action in @($Schedule.Actions)) {
        if ($null -eq $action) { continue }
        $actions.Add([ordered]@{
                action      = [string]$action.Action
                at          = [string]$action.At
                weekDays    = @($action.WeekDays)
                months      = @($action.Months)
                daysOfMonth = @($action.DaysOfMonth)
            })
    }

    [ordered]@{
        name                = [string]$Schedule.Name
        displayName         = [string]$Schedule.DisplayName
        timeZone            = [string]$Schedule.TimeZone
        actions             = $actions.ToArray()
        exceptDates         = @($Schedule.ExceptDates)
        minimumDwellMinutes = [int]$Schedule.MinimumDwellMinutes
        startGraceMinutes   = [int]$Schedule.StartGraceMinutes
    }
}
