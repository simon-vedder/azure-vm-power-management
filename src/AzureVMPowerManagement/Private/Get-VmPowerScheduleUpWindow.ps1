function Get-VmPowerScheduleUpWindow {
    <#
    .SYNOPSIS
    The shortest stretch a schedule wants its machines up for, in minutes.

    .DESCRIPTION
    A schedule is sampled, not obeyed. The controller wakes on a timer and asks what each schedule
    wants at that moment, so a window narrower than the gap between two wakes is one the controller
    can walk straight past: it is closed again by the time anybody looks. The machine is never
    started, every run reports MatchesSchedule, and nothing anywhere says why.

    Measured rather than derived from the action list, because a Start and the Deallocate that ends
    it can sit on different weekdays, and an exception date can remove either of them. Occurrences
    over a fortnight are paired up - each Start with the Deallocate that follows it - and the
    shortest pair is the answer.

    Returns nothing for a schedule that only ever starts machines. A window with no end is not a
    short one.

    .PARAMETER Schedule
    An expanded schedule, as Expand-VmPowerSchedule returns it.

    .PARAMETER FromUtc
    Where to start looking. Defaults to now.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        $Schedule,

        [Parameter()]
        [datetime]$FromUtc = [datetime]::UtcNow
    )

    $occurrences = @(Get-VmPowerScheduleOccurrence -Schedule $Schedule -FromUtc $FromUtc -Days 14 |
            Where-Object { $_.Action -in $script:ScheduleActions })

    $shortest = $null
    $openedAt = $null
    foreach ($occurrence in $occurrences) {
        if ($occurrence.Action -eq 'Start') {
            # A second Start without a Deallocate between them is not a shorter window, it is the
            # same one being reaffirmed. Keep the earliest.
            if ($null -eq $openedAt) { $openedAt = $occurrence.Utc }
            continue
        }

        if ($null -eq $openedAt) { continue }
        $minutes = [int]([math]::Round(($occurrence.Utc - $openedAt).TotalMinutes))
        if ($null -eq $shortest -or $minutes -lt $shortest) { $shortest = $minutes }
        $openedAt = $null
    }

    if ($null -ne $shortest) { $shortest }
}
