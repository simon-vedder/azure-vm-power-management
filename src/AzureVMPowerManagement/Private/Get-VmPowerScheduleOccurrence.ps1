function Get-VmPowerScheduleOccurrence {
    <#
    .SYNOPSIS
    Every action a schedule produces in a window, with the daylight saving already dealt with.

    .DESCRIPTION
    The one place that turns a schedule into instants. Show-VmPowerScheduleCalendar prints what
    this returns and the decision engine acts on it, which is the point: a preview computed by
    different code from the one that runs is a preview that eventually lies.

    Two days a year are not like the others, and both were measured against Europe/Zurich in 2026
    rather than assumed:

    Spring forward, 29 March. Local times between 02:00 and 03:00 do not exist, and
    TimeZoneInfo.ConvertTimeToUtc throws on them rather than returning something. An unhandled
    throw here would take the runbook down once a year at half past two. An action landing in the
    gap is moved to the first instant after it and marked Shifted. Forward is the safe direction
    for both actions: a start happens slightly late instead of not at all, and a stop happens
    slightly late, which is the reluctant direction anyway.

    Fall back, 25 October. Local times between 02:00 and 03:00 happen twice. .NET resolves an
    ambiguous time to standard time, which is the later of the two instants - measured: 02:30 local
    became 01:30 UTC, not 00:30. That is taken as-is and marked Ambiguous. The minimum dwell is
    what stops the doubled hour turning into a second action on the same machine.

    .PARAMETER Schedule
    A schedule in the long form, as Expand-VmPowerSchedule returns it.

    .PARAMETER FromUtc
    Start of the window in UTC. Occurrences before this are not returned. A value whose Kind is
    Local is converted; one that is Unspecified is taken as UTC.

    .PARAMETER Days
    Length of the window in local days.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerOccurrence')]
    param(
        [Parameter(Mandatory)]
        $Schedule,

        [Parameter()]
        [datetime]$FromUtc = [datetime]::UtcNow,

        [Parameter()]
        [ValidateRange(1, 400)]
        [int]$Days = 14
    )

    $tz = [System.TimeZoneInfo]::FindSystemTimeZoneById($Schedule.TimeZone)

    # A caller who writes [datetime]'2026-10-25T00:00:00Z' does not get a UTC value: PowerShell
    # converts it to the machine's local time and keeps Kind Local, so on a CEST laptop that is
    # 02:00, not 00:00. Relabelling it with SpecifyKind would move the window by the local offset
    # without saying so. The incoming Kind decides instead, and Unspecified is taken at its word.
    $fromUtcNormalised = switch ($FromUtc.Kind) {
        ([System.DateTimeKind]::Utc) { $FromUtc }
        ([System.DateTimeKind]::Local) { $FromUtc.ToUniversalTime() }
        default { [datetime]::SpecifyKind($FromUtc, [System.DateTimeKind]::Utc) }
    }
    $localNow = [System.TimeZoneInfo]::ConvertTimeFromUtc($fromUtcNormalised, $tz)
    $exceptions = @($Schedule.ExceptDates)

    $occurrences = [System.Collections.Generic.List[object]]::new()

    for ($offset = 0; $offset -lt $Days; $offset++) {
        $date = $localNow.Date.AddDays($offset)
        $isException = $exceptions -contains $date.ToString('yyyy-MM-dd')

        foreach ($action in @($Schedule.Actions)) {
            if ($action.WeekDays -notcontains [string]$date.DayOfWeek) { continue }
            if ($action.Months.Count -and $action.Months -notcontains $script:MonthNames[$date.Month - 1]) { continue }
            if ($action.DaysOfMonth.Count -and $action.DaysOfMonth -notcontains $date.Day) { continue }

            $parts = $action.At -split ':'
            $local = [datetime]::new($date.Year, $date.Month, $date.Day, [int]$parts[0], [int]$parts[1], 0, [System.DateTimeKind]::Unspecified)

            $note = ''
            if ($tz.IsInvalidTime($local)) {
                # The gap is an hour in every zone that has one, but stepping a minute at a time
                # costs nothing and does not assume that.
                $guard = 0
                while ($tz.IsInvalidTime($local) -and $guard -lt 240) { $local = $local.AddMinutes(1); $guard++ }
                $note = 'Shifted out of the daylight saving gap'
            }
            elseif ($tz.IsAmbiguousTime($local)) {
                $note = 'Ambiguous: this local time happens twice, standard time is used'
            }

            $utc = [System.TimeZoneInfo]::ConvertTimeToUtc($local, $tz)
            if ($utc -lt $fromUtcNormalised) { continue }

            $occurrences.Add([pscustomobject]@{
                    PSTypeName = $script:TypeName.Occurrence
                    Schedule   = $Schedule.Name
                    Action     = if ($isException) { 'None' } else { $action.Action }
                    LocalTime  = $local
                    Utc        = $utc
                    DayOfWeek  = [string]$date.DayOfWeek
                    Skipped    = $isException
                    Note       = if ($isException) { "Exception date $($date.ToString('yyyy-MM-dd'))" } else { $note }
                })
        }
    }

    @($occurrences | Sort-Object Utc)
}
