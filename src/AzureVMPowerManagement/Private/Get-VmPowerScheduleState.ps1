function Get-VmPowerScheduleState {
    <#
    .SYNOPSIS
    What a schedule says a machine should be right now, and how long it has said it.

    .DESCRIPTION
    The decision engine needs a desired state, not a list of future events. A machine that should
    have started at 07:30 and did not is still supposed to be running at 09:00, and an engine that
    only looked at what is due in the next hour would never notice.

    So this looks backwards. The most recent action at or before the moment asked about decides:
    Start means Up, Deallocate means Down. It uses the same occurrence engine the calendar prints,
    which is the point - a desired state derived from different code than the preview is a desired
    state nobody can check.

    Exception dates are skipped rather than treated as an action, so a machine keeps the state it
    had going into the holiday instead of flipping on a day the schedule said to do nothing.

    The lookback is forty days because a schedule can be monthly. Before that there is nothing to
    go on, and Unknown is the honest answer: not knowing is not a reason to act.

    .PARAMETER Schedule
    A schedule in the long form.

    .PARAMETER AtUtc
    The moment to answer for.

    .PARAMETER LookbackDays
    How far back to search for the last action.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        $Schedule,

        [Parameter()]
        [datetime]$AtUtc = [datetime]::UtcNow,

        [Parameter()]
        [ValidateRange(1, 400)]
        [int]$LookbackDays = 40
    )

    $at = switch ($AtUtc.Kind) {
        ([System.DateTimeKind]::Utc) { $AtUtc }
        ([System.DateTimeKind]::Local) { $AtUtc.ToUniversalTime() }
        default { [datetime]::SpecifyKind($AtUtc, [System.DateTimeKind]::Utc) }
    }

    $occurrences = Get-VmPowerScheduleOccurrence -Schedule $Schedule -FromUtc $at.AddDays(-$LookbackDays) -Days ($LookbackDays + 1)
    $last = @($occurrences | Where-Object { -not $_.Skipped -and $_.Utc -le $at }) | Select-Object -Last 1

    if (-not $last) {
        return [pscustomobject]@{ State = 'Unknown'; MinutesSince = [int]::MaxValue; At = $null }
    }

    $state = switch ($last.Action) {
        'Start' { 'Up' }
        'Deallocate' { 'Down' }
        default { 'Unknown' }
    }

    # The age matters as much as the state. A machine that is down twenty minutes after a scheduled
    # start is a start that failed; the same machine six hours later is one somebody turned off.
    [pscustomobject]@{
        State        = $state
        MinutesSince = [int][Math]::Floor(($at - $last.Utc).TotalMinutes)
        At           = $last.Utc
    }
}
