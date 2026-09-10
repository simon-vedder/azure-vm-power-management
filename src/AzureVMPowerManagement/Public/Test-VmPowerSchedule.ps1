function Test-VmPowerSchedule {
    <#
    .SYNOPSIS
    Check a schedule or a whole catalogue, and report what is wrong rather than throwing

    .DESCRIPTION
    Every path into the catalogue goes through this, which is why it reports instead of failing at
    the first problem: somebody validating twelve schedules wants all twelve answers, not the first
    one. Set-VmPowerSchedule calls it and refuses to store anything that does not pass.

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

            $result = [ordered]@{
                PSTypeName = $script:TypeName.Validation
                Name       = if ($name) { $name } else { '(unnamed)' }
                Valid      = [bool](-not $problem)
                Problem    = $problem
            }
            if ($Detailed) { $result['Schedule'] = $expanded }
            $results.Add([pscustomobject]$result)
        }

        $results
    }
}
