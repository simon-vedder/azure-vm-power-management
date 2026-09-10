function Show-VmPowerScheduleCalendar {
    <#
    .SYNOPSIS
    Print the next few days of a schedule, so a mistake is something you read rather than survive

    .DESCRIPTION
    Most schedule mistakes are not syntax errors. They are "I did not think about the Sunday", or
    "07:30 in which time zone", or a daylight saving change nobody pictured. A schema validator
    finds none of those. A printed calendar finds all three.

    It computes occurrences with the same function the decision engine uses. A preview produced by
    different code from the one that runs is a preview that eventually lies.

    Both daylight saving cases are visible in the Note column rather than being smoothed away: an
    action that fell into the spring gap shows as shifted, and one in the doubled autumn hour shows
    as ambiguous.

    .PARAMETER Schedule
    One or more schedules, in either form.

    .PARAMETER Days
    How many days ahead to render. Fourteen covers a fortnight, which is where a wrong weekday shows.

    .PARAMETER FromUtc
    Start of the window. Defaults to now, and can be set to look at a specific date - a daylight
    saving weekend, for instance.

    .EXAMPLE
    # What will this actually do?
    New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' |
        Show-VmPowerScheduleCalendar

    .EXAMPLE
    # Look straight at the daylight saving weekend rather than waiting for it
    $s | Show-VmPowerScheduleCalendar -FromUtc ([datetime]'2026-03-28T00:00:00Z') -Days 3

    .EXAMPLE
    # Everything in the catalogue, one table
    Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower |
        Show-VmPowerScheduleCalendar -Days 7 | Format-Table Schedule, DayOfWeek, LocalTime, Action, Note

    .INPUTS
    Schedules, as objects or hashtables

    .OUTPUTS
    AzureVMPowerManagement.VmPowerOccurrence

    .NOTES
    RequiredPermissions: None. This command computes times in memory.

    Prerequisites: PowerShell 7.2 or later.

    Writes: Nothing.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerOccurrence')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Schedule,

        [Parameter()]
        [ValidateRange(1, 400)]
        [int]$Days = 14,

        [Parameter()]
        [datetime]$FromUtc = [datetime]::UtcNow
    )

    begin {
        $occurrences = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in @($Schedule)) {
            if ($null -eq $entry) { continue }
            $expanded = Expand-VmPowerSchedule -Schedule $entry
            foreach ($occurrence in (Get-VmPowerScheduleOccurrence -Schedule $expanded -FromUtc $FromUtc -Days $Days)) {
                $occurrences.Add($occurrence)
            }
        }
    }

    end {
        @($occurrences | Sort-Object Utc, Schedule)
    }
}
