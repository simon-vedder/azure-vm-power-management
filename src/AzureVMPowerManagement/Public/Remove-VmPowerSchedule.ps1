function Remove-VmPowerSchedule {
    <#
    .SYNOPSIS
    Take a schedule out of the custom catalogue

    .DESCRIPTION
    Removes from PM_ScheduleCatalogCustom only. A schedule that came from the deployment cannot be
    removed here, because the deployment would put it back on the next run and the removal would
    look like it had failed. Removing an override reveals the deployment's version again rather
    than deleting anything.

    Machines still tagged with a name that no longer resolves are not left in limbo: they are
    reported as ScheduleNotInCatalogue on the next plan, which is a decision to do nothing with a
    reason attached, not a silent one. This command names them before it removes anything.

    .PARAMETER Name
    Schedules to remove.

    .PARAMETER ResourceGroupName
    Resource group holding the Automation Account.

    .PARAMETER AutomationAccountName
    The Automation Account.

    .PARAMETER SubscriptionId
    Subscription holding the account. Defaults to the current context.

    .EXAMPLE
    # Drop an override and let the shipped example apply again
    Remove-VmPowerSchedule -Name office-hours-ch -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower

    .EXAMPLE
    # See what would happen first
    Remove-VmPowerSchedule -Name night-shift -ResourceGroupName rg-vmpower -AutomationAccountName aa-vmpower -WhatIf

    .INPUTS
    None

    .OUTPUTS
    None

    .NOTES
    RequiredPermissions: Microsoft.Automation/automationAccounts/variables/write and /read on the
    Automation Account.

    Prerequisites: PowerShell 7.2 or later and Az.Accounts.

    Writes: The Automation variable PM_ScheduleCatalogCustom.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string[]]$Name,

        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$AutomationAccountName,

        [Parameter()]
        [string]$SubscriptionId
    )

    begin {
        $wanted = [System.Collections.Generic.List[string]]::new()
    }

    process {
        foreach ($entry in @($Name)) { if ($entry) { $wanted.Add($entry) } }
    }

    end {
        if (-not $wanted.Count) { return }

        $common = @{ ResourceGroupName = $ResourceGroupName; AutomationAccountName = $AutomationAccountName }
        if ($SubscriptionId) { $common['SubscriptionId'] = $SubscriptionId }
        $variable = $script:CatalogVariable.Custom

        $existing = [ordered]@{}
        foreach ($entry in (Get-VmPowerCatalogVariable @common -VariableName $variable)) {
            if ($null -eq $entry) { continue }
            $expanded = Expand-VmPowerSchedule -Schedule $entry
            $existing[$expanded.Name] = $expanded
        }

        $present = @($wanted | Where-Object { $existing.Contains($_) })
        $absent = @($wanted | Where-Object { -not $existing.Contains($_) })

        foreach ($missing in $absent) {
            Write-Warning "'$missing' is not in the custom catalogue, so there is nothing to remove. If it came from the deployment, change it there."
        }
        if (-not $present.Count) { return }

        if (-not $PSCmdlet.ShouldProcess("$AutomationAccountName/$variable", "Remove $($present -join ', ')")) { return }

        foreach ($entry in $present) { $existing.Remove($entry) }
        # Same reason as in Set-VmPowerSchedule: the values are taken as an explicit list rather
        # than relying on how a dictionary's Values collection unrolls.
        $remaining = [System.Collections.Generic.List[object]]::new()
        foreach ($key in @($existing.Keys)) { $remaining.Add($existing[$key]) }
        Set-VmPowerCatalogVariable @common -VariableName $variable -Catalog $remaining.ToArray()
    }
}
