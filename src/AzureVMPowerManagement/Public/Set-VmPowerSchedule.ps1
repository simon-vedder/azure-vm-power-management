function Set-VmPowerSchedule {
    <#
    .SYNOPSIS
    Store a schedule in the catalogue, without a redeployment

    .DESCRIPTION
    Writes into PM_ScheduleCatalogCustom, which the deployment never touches. That split is the
    whole reason there are two variables: one owned by infrastructure as code, one owned by whoever
    is on the end of a phone at half past five - see docs/decisions/0005.

    A schedule with a name that already exists in the custom catalogue replaces it. A name that
    exists only in the deployment catalogue is shadowed rather than changed, so the shipped example
    stays intact and a later redeployment does not fight the override.

    Everything is validated before anything is written, and the write is one replacement of the
    whole variable rather than an append, so a half-written catalogue is not a state this can leave
    behind.

    .PARAMETER Schedule
    Schedules to store, from New-VmPowerSchedule or read back from a file.

    .PARAMETER ResourceGroupName
    Resource group holding the Automation Account.

    .PARAMETER AutomationAccountName
    The Automation Account.

    .PARAMETER SubscriptionId
    Subscription holding the account. Defaults to the current context.

    .PARAMETER PassThru
    Return the stored schedules.

    .EXAMPLE
    # The one-liner this whole design exists for
    New-VmPowerSchedule -Name office-hours-ch -TimeZone 'Europe/Zurich' -Weekdays '07:30-18:30' |
        Set-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower

    .EXAMPLE
    # Look before you store
    $s = New-VmPowerSchedule -Name night-shift -TimeZone 'Europe/Zurich' -Daily '22:00-06:00'
    $s | Show-VmPowerScheduleCalendar -Days 3
    $s | Set-VmPowerSchedule -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower

    .INPUTS
    AzureVMPowerManagement.VmPowerSchedule

    .OUTPUTS
    AzureVMPowerManagement.VmPowerSchedule when -PassThru is given, otherwise nothing

    .NOTES
    RequiredPermissions: Microsoft.Automation/automationAccounts/variables/write and /read on the
    Automation Account. Automation Contributor covers it; a custom role limited to those two actions
    is narrower and is what a person authoring schedules should have.

    Prerequisites: PowerShell 7.2 or later and Az.Accounts.

    Writes: The Automation variable PM_ScheduleCatalogCustom. It never writes PM_ScheduleCatalog,
    which belongs to the deployment.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('AzureVMPowerManagement.VmPowerSchedule')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object[]]$Schedule,

        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$AutomationAccountName,

        [Parameter()]
        [string]$SubscriptionId,

        [Parameter()]
        [switch]$PassThru
    )

    begin {
        $incoming = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($entry in @($Schedule)) {
            if ($null -ne $entry) { $incoming.Add($entry) }
        }
    }

    end {
        if (-not $incoming.Count) { return }

        # Validate everything first. A run that stored three schedules and then threw on the fourth
        # would leave a catalogue nobody asked for.
        $checked = @($incoming | Test-VmPowerSchedule -Detailed)
        $bad = @($checked | Where-Object { -not $_.Valid })
        if ($bad.Count) {
            throw ("Nothing was stored. $($bad.Count) schedule(s) did not validate: " +
                (($bad | ForEach-Object { "$($_.Name): $($_.Problem)" }) -join ' | '))
        }

        $common = @{ ResourceGroupName = $ResourceGroupName; AutomationAccountName = $AutomationAccountName }
        if ($SubscriptionId) { $common['SubscriptionId'] = $SubscriptionId }
        $variable = $script:CatalogVariable.Custom

        $existing = [ordered]@{}
        foreach ($entry in (Get-VmPowerCatalogVariable @common -VariableName $variable)) {
            if ($null -eq $entry) { continue }
            $expanded = Expand-VmPowerSchedule -Schedule $entry
            $existing[$expanded.Name] = $expanded
        }

        # Not $schedule. PowerShell variable names are case-insensitive, so a loop variable spelled
        # that way IS this function's [object[]]$Schedule parameter, and every assignment to it is
        # silently coerced into a one-element array. The catalogue then serialised as a nested array
        # that the reader could only describe as "a schedule with no name". Found against a real
        # Automation Account on 2026-09-10; a typed parameter makes its own name unusable as a local.
        $replaced = @()
        $stored = [System.Collections.Generic.List[object]]::new()
        foreach ($result in $checked) {
            $expanded = $result.Schedule
            if ($existing.Contains($expanded.Name)) { $replaced += $expanded.Name }
            $existing[$expanded.Name] = $expanded
            $stored.Add($expanded)
        }

        $target = "$AutomationAccountName/$variable"
        # Select-Object, not ForEach-Object Name: the member form of ForEach-Object supports
        # ShouldProcess, so under -WhatIf it produces its own confirmation line and returns nothing,
        # and the message that is meant to say which schedules are involved says none of them.
        $names = @($stored | Select-Object -ExpandProperty Name) -join ', '
        $what = "Store $($stored.Count) schedule(s): $names" +
        $(if ($replaced) { " (replacing $($replaced -join ', '))" } else { '' })

        if (-not $PSCmdlet.ShouldProcess($target, $what)) { return }

        $toStore = [System.Collections.Generic.List[object]]::new()
        foreach ($key in @($existing.Keys)) { $toStore.Add($existing[$key]) }
        Set-VmPowerCatalogVariable @common -VariableName $variable -Catalog $toStore.ToArray()

        if ($PassThru) { $stored }
    }
}
