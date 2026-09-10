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
      Dwell         A machine this tool acted on within -MinimumDwellMinutes is left alone.
                    Azure bills a five-minute minimum per start, so a flapping schedule costs money
                    as well as being wrong. It needs -LastActionAt: with no memory of the previous
                    run there is nothing to compare against, and the guard stands down.

    Deallocation is the only action version one performs, and it uses Stop-AzVM, which requests a
    graceful shutdown and then releases the host. A machine already in PowerState/stopped has no
    running operating system to shut down, so in practice this is a pure deallocate.

    The Az context is pointed at each machine's own subscription before it is acted on. Stop-AzVM
    and Start-AzVM take no subscription: they act wherever the context happens to point, while
    discovery answers for every subscription the identity can read. Left alone, a plan spanning
    three subscriptions fails on two of them - or worse, finds a machine of the same name in the
    same resource group name somewhere else and deallocates that one instead.

    .PARAMETER Plan
    Decisions from Get-VmPowerPlan. Items with an action of None are counted and skipped.

    .PARAMETER MaximumActions
    Refuse the entire run if more than this many machines would be acted on. There is no default
    that is right for somebody else's estate, so this is mandatory.

    .PARAMETER MinimumDwellMinutes
    Leave a machine alone if this tool acted on it more recently than this. Zero switches the check
    off entirely, whatever a schedule asks for. Above zero it is a floor: a schedule carrying its own
    minimumDwellMinutes can ask for longer, never shorter. A guard the thing being guarded can
    weaken is not a guard.

    .PARAMETER LastActionAt
    Map of resource id to the time this tool last acted on it, for the dwell check. Values may be
    DateTime or a round-trip string. Empty - the default - means there is no memory of a previous
    run, and the dwell check has nothing to compare against. The runbook passes what it recorded in
    the Automation variable PM_LastActionAt.

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

            # The run-wide setting is a floor, not the last word: a schedule whose machines take
            # twenty minutes to come up may ask for a longer dwell than the default thirty. It
            # cannot ask for a shorter one. Zero on the run-wide setting means off, and a schedule
            # cannot turn it back on either - the operator's switch beats the author's.
            $dwell = 0
            if ($MinimumDwellMinutes -gt 0) {
                $dwell = $MinimumDwellMinutes
                if ($item.PSObject.Properties.Name -contains 'MinimumDwellMinutes' -and $null -ne $item.MinimumDwellMinutes) {
                    $dwell = [Math]::Max($dwell, [int]$item.MinimumDwellMinutes)
                }
            }

            if (-not $skip -and $dwell -gt 0 -and $LastActionAt.ContainsKey($item.Id)) {
                # An unreadable timestamp leaves the machine alone and says so. Treating it as
                # "no memory" would silently stand the guard down, which is the one outcome a
                # corrupt safety store must not produce.
                $lastUtc = $null
                try { $lastUtc = ConvertTo-VmPowerUtcTime -Value $LastActionAt[$item.Id] }
                catch { $skip = "The dwell store holds '$($LastActionAt[$item.Id])' for this machine, which is not a time. Nothing was done to it." }

                if ($lastUtc) {
                    $since = $now - $lastUtc
                    if ($since.TotalMinutes -lt $dwell) {
                        $skip = "Acted on $([int]$since.TotalMinutes) minute(s) ago, inside the $dwell minute dwell"
                    }
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
                Switch-VmPowerSubscriptionContext -SubscriptionId ([string]$item.SubscriptionId)
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
