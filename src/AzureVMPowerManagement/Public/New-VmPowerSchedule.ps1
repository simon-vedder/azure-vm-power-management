function New-VmPowerSchedule {
    <#
    .SYNOPSIS
    Build a schedule from parameters instead of writing the JSON by hand

    .DESCRIPTION
    JSON is what a schedule is stored as, the way ARM JSON is what Bicep is stored as. This is the
    door you author through: friendly parameters in, a validated schedule out, and a clear error
    rather than a schedule that misbehaves at half past six.

    The object it returns is the long form - a list of actions, each with one action type, because
    that is how Microsoft.ComputeSchedule models one. Pipe it to Set-VmPowerSchedule to store it, or
    to Show-VmPowerScheduleCalendar to see what it will actually do before anything else sees it.

    .PARAMETER Name
    Catalogue name, and the value machines carry in their PowerSchedule tag. Lowercase letters,
    digits and hyphens, 3 to 40 characters, because it is also an allowedValues entry in the
    generated policy.

    .PARAMETER TimeZone
    Windows form ('W. Europe Standard Time') or IANA form ('Europe/Zurich'). Both resolve on the
    Linux workers that run PowerShell 7.2 in Azure Automation.

    .PARAMETER Weekdays
    Shorthand for Monday to Friday, as 'HH:mm-HH:mm'. Compiles into a Start and a Deallocate.

    .PARAMETER Daily
    The same shorthand, every day of the week.

    .PARAMETER Days
    Days the explicit form applies to. Defaults to every day.

    .PARAMETER Start
    Time to start the machines, in the explicit form.

    .PARAMETER Stop
    Time to deallocate them. Omit for a schedule that starts machines and never stops them.

    .PARAMETER ExceptDate
    Dates to skip, as yyyy-MM-dd. No holiday calendar ships with this tool: Switzerland alone has
    cantonal holidays, and a calendar that looks authoritative and is wrong is worse than none.

    .PARAMETER MinimumDwellMinutes
    Leave a machine alone for this long after acting on it. Azure bills a five-minute minimum per
    start, so a schedule that flaps costs money as well as being wrong.

    .PARAMETER DisplayName
    Human label for the workbook. Defaults to the name.

    .EXAMPLE
    # The common case, in one line
    New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30'

    .EXAMPLE
    # Explicit days, and a Friday that ends earlier is a second schedule rather than a special case
    New-VmPowerSchedule -Name build-agents -TimeZone 'UTC' -Days Monday, Tuesday, Wednesday, Thursday -Start 06:00 -Stop 22:00

    .EXAMPLE
    # Managed but never stopped: better than leaving a machine untagged, because untagged is
    # indistinguishable from forgotten
    New-VmPowerSchedule -Name always-on -TimeZone 'Europe/Zurich' -Start 06:00

    .EXAMPLE
    # See what it does before storing it
    New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' -ExceptDate 2026-12-24, 2026-12-25 |
        Show-VmPowerScheduleCalendar -Days 14

    .INPUTS
    None

    .OUTPUTS
    AzureVMPowerManagement.VmPowerSchedule

    .NOTES
    RequiredPermissions: None. This command builds an object and touches nothing.

    Prerequisites: PowerShell 7.2 or later.

    Writes: Nothing. Storing the result is Set-VmPowerSchedule's job.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Shorthand')]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'New- is a state-changing verb, but this builds an object in memory and touches nothing. Set-VmPowerSchedule is where anything is stored, and that is where ShouldProcess belongs.')]
    [OutputType('AzureVMPowerManagement.VmPowerSchedule')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$TimeZone,

        [Parameter(Mandatory, ParameterSetName = 'Shorthand')]
        [string]$Weekdays,

        [Parameter(Mandatory, ParameterSetName = 'Daily')]
        [string]$Daily,

        [Parameter(ParameterSetName = 'Explicit')]
        [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
        [string[]]$Days,

        [Parameter(Mandatory, ParameterSetName = 'Explicit')]
        [string]$Start,

        [Parameter(ParameterSetName = 'Explicit')]
        [string]$Stop,

        [Parameter()]
        [string[]]$ExceptDate,

        [Parameter()]
        [ValidateRange(0, 1440)]
        [int]$MinimumDwellMinutes = 30,

        [Parameter()]
        [string]$DisplayName
    )

    $raw = @{
        name                = $Name
        timeZone            = $TimeZone
        exceptDates         = @($ExceptDate)
        minimumDwellMinutes = $MinimumDwellMinutes
    }
    if ($DisplayName) { $raw['displayName'] = $DisplayName }

    switch ($PSCmdlet.ParameterSetName) {
        'Shorthand' { $raw['weekdays'] = $Weekdays }
        'Daily' { $raw['daily'] = $Daily }
        'Explicit' {
            $applyTo = if ($Days) { $Days } else { 'All' }
            $actions = @(@{ action = 'Start'; at = $Start; weekDays = $applyTo })
            if ($Stop) { $actions += @{ action = 'Deallocate'; at = $Stop; weekDays = $applyTo } }
            $raw['actions'] = $actions
        }
    }

    Expand-VmPowerSchedule -Schedule $raw
}
