function Test-VmPowerSchedule {
    <#
    .SYNOPSIS
    Check a schedule or a whole catalogue, and report what is wrong rather than throwing

    .DESCRIPTION
    Every path into the catalogue goes through this, which is why it reports instead of failing at
    the first problem: somebody validating twelve schedules wants all twelve answers, not the first
    one. Set-VmPowerSchedule calls it and refuses to store anything that does not pass.

    Valid and useful are different questions. A schedule can be well formed and still be one the
    deployed controller never sees open, because it is sampled on a timer that cannot run more often
    than hourly. That comes back in Warnings rather than Problem: nothing is wrong with the schedule,
    but left alone it would do nothing and say nothing about it.

    It also checks the things a schema cannot: two schedules with the same name, and a catalogue
    whose names would not survive being turned into the allowedValues of a policy.

    Pass -Detailed to get the expanded schedule back alongside the verdict, which is what
    Show-VmPowerScheduleCalendar consumes.

    .PARAMETER Schedule
    One schedule or a catalogue of them, in either the shorthand or the long form.

    .PARAMETER Detailed
    Include the expanded schedule on each result.

    .EXAMPLE
    # Validate a catalogue read out of a file before it goes anywhere near a deployment
    Get-Content ./catalog.json -Raw | ConvertFrom-Json | Test-VmPowerSchedule | Format-Table Name, Valid, Problem

    .EXAMPLE
    # The one-liner before storing
    New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' | Test-VmPowerSchedule

    .INPUTS
    Schedules, as objects or hashtables

    .OUTPUTS
    AzureVMPowerManagement.VmPowerScheduleValidation

    .NOTES
    RequiredPermissions: None. This command reads objects in memory.

    Prerequisites: PowerShell 7.2 or later.

    Writes: Nothing.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerScheduleValidation')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object[]]$Schedule,

        [Parameter()]
        [switch]$Detailed
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in @($Schedule)) {
            if ($null -ne $entry) { $collected.Add($entry) }
        }
    }

    end {
        $results = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.Dictionary[string, int]]::new([System.StringComparer]::OrdinalIgnoreCase)

        foreach ($entry in $collected) {
            $name = [string](ConvertTo-VmPowerHashtable -InputObject $entry)['name']
            $expanded = $null
            $problem = ''
            try { $expanded = Expand-VmPowerSchedule -Schedule $entry }
            catch { $problem = $_.Exception.Message }

            if (-not $problem -and $expanded) {
                $name = $expanded.Name
                if ($seen.ContainsKey($name)) {
                    # A duplicate is not a schema error, and it is the one that bites: the second
                    # entry silently wins and nobody can see which of the two is running.
                    $problem = "Duplicate name. '$name' appears more than once in this catalogue, and only one of them can apply."
                }
                else { $seen[$name] = 1 }
            }

            # Not a problem: the schedule is well formed and somebody triggering the runbook by
            # webhook every ten minutes would be served by it exactly as written. It is a warning
            # because the deployed controller cannot wake more often than hourly, so a window this
            # narrow is one it will usually step over - and the symptom is silence. Every run says
            # MatchesSchedule, the machine is never started, and nothing is wrong anywhere.
            $warnings = [System.Collections.Generic.List[string]]::new()
            if (-not $problem -and $null -ne $expanded) {
                $window = Get-VmPowerScheduleUpWindow -Schedule @($expanded)[0]
                if ($null -ne $window -and $window -lt $script:MinimumTriggerMinutes) {
                    $warnings.Add("Wants machines up for only $window minute(s) at a time. An Azure Automation schedule cannot run more often than every $script:MinimumTriggerMinutes minutes, so the controller will usually wake after the window has closed and never start anything. Widen the window, or trigger the runbook by webhook.")
                }
            }

            $result = [ordered]@{
                PSTypeName = $script:TypeName.Validation
                Name       = if ($name) { $name } else { '(unnamed)' }
                Valid      = [bool](-not $problem)
                Problem    = $problem
                Warnings   = $warnings.ToArray()
            }
            # @(...)[0] because a collection landing on this property becomes a nested array in
            # anything that stores the result, and the read side can only report a schedule with
            # no name. Expand-VmPowerSchedule returns one object; this makes that true here too.
            if ($Detailed) { $result['Schedule'] = if ($null -eq $expanded) { $null } else { @($expanded)[0] } }
            $results.Add([pscustomobject]$result)
        }

        $results
    }
}
