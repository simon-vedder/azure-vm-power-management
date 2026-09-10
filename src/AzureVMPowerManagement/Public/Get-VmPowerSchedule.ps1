function Get-VmPowerSchedule {
    <#
    .SYNOPSIS
    Read the schedule catalogue out of an Automation Account

    .DESCRIPTION
    The catalogue lives in two Automation variables and this merges them. PM_ScheduleCatalog is
    owned and overwritten by the deployment and holds the examples that ship. PM_ScheduleCatalogCustom
    is written only by Set-VmPowerSchedule and the deployment never touches it.

    A custom entry wins on a name collision, so an example can be overridden without being edited
    and a redeployment never eats somebody's work. Every schedule comes back with the Source it came
    from, because "why did my change not take effect" is otherwise unanswerable.

    Each entry is expanded and validated on the way out, so a catalogue that was edited by hand in
    the portal fails here rather than halfway through a run.

    .PARAMETER ResourceGroupName
    Resource group holding the Automation Account.

    .PARAMETER AutomationAccountName
    The Automation Account the deployment created.

    .PARAMETER SubscriptionId
    Subscription holding the account. Defaults to the current context.

    .PARAMETER Name
    Return only these schedules.

    .PARAMETER Source
    Read only one of the two variables, rather than the merged view.

    .EXAMPLE
    # The whole catalogue, and where each entry came from
    Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower |
        Format-Table Name, TimeZone, Source

    .EXAMPLE
    # What one schedule will actually do over the next fortnight
    Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower -Name office-hours-ch |
        Show-VmPowerScheduleCalendar

    .EXAMPLE
    # The plan for the whole estate, using the catalogue the runbook would use
    $catalog = Get-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower
    Get-VmPowerPlan -Schedule $catalog | Format-Table Name, Schedule, PowerState, Action, Reason

    .INPUTS
    None

    .OUTPUTS
    AzureVMPowerManagement.VmPowerSchedule

    .NOTES
    RequiredPermissions: Microsoft.Automation/automationAccounts/variables/read on the Automation
    Account. Reader on the account covers it.

    Prerequisites: PowerShell 7.2 or later and Az.Accounts.

    Writes: Nothing.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerSchedule')]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$AutomationAccountName,

        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [string[]]$Name,

        [Parameter()]
        [ValidateSet('Deployment', 'Custom')]
        [string]$Source
    )

    $common = @{ ResourceGroupName = $ResourceGroupName; AutomationAccountName = $AutomationAccountName }
    if ($SubscriptionId) { $common['SubscriptionId'] = $SubscriptionId }

    $wanted = if ($Source) { , $Source } else { 'Deployment', 'Custom' }
    $merged = [ordered]@{}

    # Deployment first, custom second: the second write wins, which is the collision rule.
    foreach ($origin in 'Deployment', 'Custom') {
        if ($origin -notin $wanted) { continue }
        $variable = $script:CatalogVariable[$origin]
        foreach ($entry in (Get-VmPowerCatalogVariable @common -VariableName $variable)) {
            if ($null -eq $entry) { continue }
            $expanded = Expand-VmPowerSchedule -Schedule $entry
            $expanded | Add-Member -NotePropertyName 'Source' -NotePropertyValue $origin -Force
            $merged[$expanded.Name] = $expanded
        }
    }

    foreach ($schedule in $merged.Values) {
        if ($Name -and $schedule.Name -notin $Name) { continue }
        $schedule
    }
}
