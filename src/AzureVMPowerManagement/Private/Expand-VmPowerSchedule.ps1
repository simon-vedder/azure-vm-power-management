function Expand-VmPowerSchedule {
    <#
    .SYNOPSIS
    Normalise a schedule into the long form the engine reads, or say precisely what is wrong.

    .DESCRIPTION
    The stored form is a list of actions, because that is how Microsoft.ComputeSchedule models one:
    a scheduled action carries exactly one actionType. "Office hours" is two actions, not a window.
    Authoring in that form is tedious, so a shorthand compiles into it and everything downstream -
    the calendar, the rules, and one day the handover to Azure - sees only the long form.

    Nothing here calls Azure, and nothing here guesses. A schedule that cannot be understood throws
    with the reason rather than being silently repaired into something nobody asked for.

    .PARAMETER Schedule
    A schedule as a hashtable or an object, in either the shorthand or the long form.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerSchedule')]
    param(
        [Parameter(Mandatory)]
        $Schedule
    )

    # A collection here means somebody handed over a list where one schedule belongs. Without this
    # the name comes out empty and the error blames the schedule for a mistake made two functions
    # earlier - which is exactly what happened on 2026-09-10.
    if ($Schedule -is [System.Collections.IEnumerable] -and
        $Schedule -isnot [string] -and
        $Schedule -isnot [System.Collections.IDictionary]) {
        throw 'Expand-VmPowerSchedule was given a collection. It takes one schedule; pass them one at a time.'
    }

    $raw = ConvertTo-VmPowerHashtable -InputObject $Schedule

    $name = [string]$raw['name']
    # -cnotmatch, not -notmatch. PowerShell's -match is case-insensitive, so a lowercase-only
    # pattern silently accepts 'Office-Hours' - which is exactly the value this check exists to
    # reject, because it has to survive being a tag value and a policy allowedValues entry.
    if ($name -cnotmatch $script:ScheduleNamePattern) {
        throw ("Schedule name '$name' is not usable. It has to be 3 to 40 characters of lowercase " +
            'letters, digits and hyphens, starting and ending with a letter or digit, because the name ' +
            'is also a tag value and an allowedValues entry in the generated policy.')
    }

    $timeZoneId = [string]$raw['timeZone']
    if (-not $timeZoneId) { throw "Schedule '$name' has no timeZone. There is no sensible default: a schedule without one is a schedule in somebody else's morning." }
    try { $null = [System.TimeZoneInfo]::FindSystemTimeZoneById($timeZoneId) }
    catch { throw "Schedule '$name' names the time zone '$timeZoneId', which this runtime cannot resolve. Both the Windows form ('W. Europe Standard Time') and the IANA form ('Europe/Zurich') work." }

    # Shorthand first: weekdays '07:30-18:30' is the case almost everybody wants, and writing it as
    # two action entries by hand is how people end up with a stop and no start.
    $actions = [System.Collections.Generic.List[object]]::new()
    $shorthand = [string]$raw['weekdays']
    $shorthandDaily = [string]$raw['daily']

    if ($shorthand -and $shorthandDaily) { throw "Schedule '$name' sets both 'weekdays' and 'daily'. Pick one." }
    if (($shorthand -or $shorthandDaily) -and $raw['actions']) { throw "Schedule '$name' mixes a shorthand with an explicit 'actions' list. Pick one." }

    if ($shorthand -or $shorthandDaily) {
        $span = if ($shorthand) { $shorthand } else { $shorthandDaily }
        $days = if ($shorthand) { $script:WeekDayNames[0..4] } else { $script:WeekDayNames }
        if ($span -notmatch '^\s*(\d{1,2}:\d{2})\s*-\s*(\d{1,2}:\d{2})\s*$') {
            throw "Schedule '$name' has the span '$span', which is not 'HH:mm-HH:mm'."
        }
        $actions.Add(@{ action = 'Start'; at = $Matches[1]; weekDays = $days })
        $actions.Add(@{ action = 'Deallocate'; at = $Matches[2]; weekDays = $days })
    }
    else {
        foreach ($entry in @($raw['actions'])) {
            if ($null -eq $entry) { continue }
            $actions.Add((ConvertTo-VmPowerHashtable -InputObject $entry))
        }
    }

    if (-not $actions.Count) {
        throw "Schedule '$name' has no actions. A schedule that does nothing is better expressed by not tagging the machine."
    }

    $normalised = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $actions) {
        $action = [string]$entry['action']
        if ($action -notin $script:ScheduleActions) {
            throw "Schedule '$name' has the action '$action'. Allowed: $($script:ScheduleActions -join ', ')."
        }

        $at = [string]$entry['at']
        if ($at -notmatch '^(\d{1,2}):(\d{2})$' -or [int]$Matches[1] -gt 23 -or [int]$Matches[2] -gt 59) {
            throw "Schedule '$name' has the time '$at' on its $action action. Expected HH:mm in 24-hour form."
        }
        $at = '{0:00}:{1:00}' -f [int]$Matches[1], [int]$Matches[2]

        $weekDays = Resolve-VmPowerNameList -Value $entry['weekDays'] -Allowed $script:WeekDayNames -Label "weekDays on the $action action of '$name'"
        $months = Resolve-VmPowerNameList -Value $entry['months'] -Allowed $script:MonthNames -Label "months on the $action action of '$name'"

        $daysOfMonth = @()
        foreach ($day in @($entry['daysOfMonth'])) {
            if ($null -eq $day -or "$day" -eq '') { continue }
            $number = 0
            if (-not [int]::TryParse("$day", [ref]$number) -or $number -lt 1 -or $number -gt 31) {
                throw "Schedule '$name' has the day of month '$day' on its $action action. Expected 1 to 31."
            }
            $daysOfMonth += $number
        }

        $normalised.Add([pscustomobject]@{
                Action      = $action
                At          = $at
                WeekDays    = $weekDays
                Months      = $months
                DaysOfMonth = @($daysOfMonth | Sort-Object -Unique)
            })
    }

    $exceptDates = @()
    foreach ($date in @($raw['exceptDates'])) {
        if ($null -eq $date -or "$date" -eq '') { continue }
        $parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact("$date", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) {
            throw "Schedule '$name' has the exception date '$date'. Expected yyyy-MM-dd."
        }
        $exceptDates += $parsed.ToString('yyyy-MM-dd')
    }

    $dwell = 0
    if ($null -ne $raw['minimumDwellMinutes'] -and "$($raw['minimumDwellMinutes'])" -ne '') {
        if (-not [int]::TryParse("$($raw['minimumDwellMinutes'])", [ref]$dwell) -or $dwell -lt 0 -or $dwell -gt 1440) {
            throw "Schedule '$name' has minimumDwellMinutes '$($raw['minimumDwellMinutes'])'. Expected 0 to 1440."
        }
    }

    [pscustomobject]@{
        PSTypeName          = $script:TypeName.Schedule
        Name                = $name
        DisplayName         = if ($raw['displayName']) { [string]$raw['displayName'] } else { $name }
        TimeZone            = $timeZoneId
        Actions             = @($normalised)
        ExceptDates         = @($exceptDates | Sort-Object -Unique)
        MinimumDwellMinutes = $dwell
    }
}
