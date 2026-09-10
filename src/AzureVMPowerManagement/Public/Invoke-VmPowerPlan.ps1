function Invoke-VmPowerPlan {
    <#
    .SYNOPSIS
    Carry out a plan, after the guards agree to it

    .DESCRIPTION
    Takes the decisions Get-VmPowerPlan produced and performs the ones the guards allow. The plan
    is computed once and consumed here, so an armed run and a dry run cannot drift apart.

    Four guards stand between a plan and a machine, and all four refuse loudly rather than quietly:

      Confirm       Every action goes through ShouldProcess, so -WhatIf previews the whole run.
      Protected     A machine carrying the exclusion tag is never touched, whatever the plan says.
      Blast radius  A run that would act on more machines than -MaximumActions performs none of
                    them. A mistake broad enough to matter becomes a report, not an incident.
      Dwell         A machine acted on within -MinimumDwellMinutes is left alone. Azure bills a
                    five-minute minimum per start, so a flapping schedule costs money as well as
                    being wrong.

    Deallocation is the only action version one performs, and it uses Stop-AzVM, which requests a
    graceful shutdown and then releases the host. A machine already in PowerState/stopped has no
    running operating system to shut down, so in practice this is a pure deallocate.

    .PARAMETER Plan
    Decisions from Get-VmPowerPlan. Items with an action of None are counted and skipped.

    .PARAMETER MaximumActions
    Refuse the entire run if more than this many machines would be acted on. There is no default
    that is right for somebody else's estate, so this is mandatory.

    .PARAMETER MinimumDwellMinutes
    Leave a machine alone if it changed power state more recently than this. Zero disables the check.

    .PARAMETER LastActionAt
    Map of resource id to the time this tool last acted on it, for the dwell check. The runbook
    passes what it recorded on the previous run.

    .EXAMPLE
    # Preview everything an armed run would do, and change nothing
    Get-VmPowerPlan -ActionableOnly | Invoke-VmPowerPlan -MaximumActions 50 -WhatIf

    .EXAMPLE
    # Deallocate the machines that are powered off and still billed, at most twenty of them
    Get-VmPowerPlan -ActionableOnly | Invoke-VmPowerPlan -MaximumActions 20

    .INPUTS
    AzureVMPowerManagement.VmPowerPlan

    .OUTPUTS
    AzureVMPowerManagement.VmPowerPlanResult

    .NOTES
    RequiredPermissions: Microsoft.Compute/virtualMachines/deallocate/action and
    Microsoft.Compute/virtualMachines/read on every machine in scope, or their resource groups.
    Virtual Machine Contributor covers both and a great deal more, so a custom role limited to
    those two actions plus Microsoft.Compute/virtualMachines/start/action is the narrower choice
    and is what deploy/main.bicep creates.

    Prerequisites: PowerShell 7.2 or later, and the modules Az.Accounts and Az.Compute.

    Writes: Deallocates virtual machines. This is the command that can cost somebody an outage,
    which is why every guard above defaults to refusing.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    [OutputType('AzureVMPowerManagement.VmPowerPlanResult')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [PSTypeName('AzureVMPowerManagement.VmPowerPlan')]
        [object[]]$Plan,

        [Parameter(Mandatory)]
        [ValidateRange(1, 10000)]
        [int]$MaximumActions,

        [Parameter()]
        [ValidateRange(0, 1440)]
        [int]$MinimumDwellMinutes = 30,

        [Parameter()]
        [hashtable]$LastActionAt = @{}
    )

    begin {
        $collected = [System.Collections.Generic.List[object]]::new()
    }

    process {
        foreach ($item in @($Plan)) {
            if ($null -ne $item) { $collected.Add($item) }
        }
    }

    end {
        $actionable = @($collected | Where-Object { $_.Action -ne 'None' -and -not $_.Protected })
        $now = [datetime]::UtcNow

        # The blast radius is checked against the whole plan before anything happens. Checking it
        # per machine would let a run act on the first n and then stop, which is the worst of both.
        if ($actionable.Count -gt $MaximumActions) {
            throw ("The plan would act on $($actionable.Count) machine(s), more than the $MaximumActions allowed. " +
                'Nothing was done. Raise -MaximumActions if this is expected, or look at the plan first: ' +
                'a jump in this number usually means a tag or a schedule changed, not that the estate did.')
        }

        foreach ($item in $collected) {
            $skip = switch ($true) {
                ($item.Protected) { $item.ProtectedReason; break }
                ($item.Action -eq 'None') { $item.Reason; break }
                default { $null }
            }

            if (-not $skip -and $MinimumDwellMinutes -gt 0 -and $LastActionAt.ContainsKey($item.Id)) {
                $since = $now - ([datetime]$LastActionAt[$item.Id]).ToUniversalTime()
                if ($since.TotalMinutes -lt $MinimumDwellMinutes) {
                    $skip = "Acted on $([int]$since.TotalMinutes) minute(s) ago, inside the $MinimumDwellMinutes minute dwell"
                }
            }

            if ($skip) {
                [pscustomobject]@{
                    PSTypeName = $script:TypeName.Result
                    Id         = $item.Id
                    Name       = $item.Name
                    Action     = $item.Action
                    Status     = 'Skipped'
                    Detail     = $skip
                    Timestamp  = $now
                }
                continue
            }

            $target = "$($item.Name) in $($item.ResourceGroup)"
            if (-not $PSCmdlet.ShouldProcess($target, "$($item.Action) - $($item.Reason)")) {
                [pscustomobject]@{
                    PSTypeName = $script:TypeName.Result
                    Id         = $item.Id
                    Name       = $item.Name
                    Action     = $item.Action
                    Status     = 'WhatIf'
                    Detail     = $item.Explanation
                    Timestamp  = $now
                }
                continue
            }

            $status, $detail = try {
                switch ($item.Action) {
                    'Deallocate' {
                        $null = Stop-AzVM -ResourceGroupName $item.ResourceGroup -Name $item.Name -Force -ErrorAction Stop
                        'Done', $item.Explanation
                    }
                    'Start' {
                        $null = Start-AzVM -ResourceGroupName $item.ResourceGroup -Name $item.Name -ErrorAction Stop
                        'Done', $item.Explanation
                    }
                    default { 'Skipped', "No handler for action $($item.Action)" }
                }
            }
            catch {
                # One machine failing is not a reason to abandon the rest, and the reason has to
                # survive into the ledger or nobody can answer why a machine is still running.
                'Failed', $_.Exception.Message
            }

            [pscustomobject]@{
                PSTypeName = $script:TypeName.Result
                Id         = $item.Id
                Name       = $item.Name
                Action     = $item.Action
                Status     = $status
                Detail     = $detail
                Timestamp  = $now
            }
        }
    }
}
