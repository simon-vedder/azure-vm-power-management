function Get-VmPowerPlan {
    <#
    .SYNOPSIS
    Work out what should happen to the virtual machines in scope, and change nothing

    .DESCRIPTION
    Reads every virtual machine the caller can see through Azure Resource Graph, applies the rules
    to each one, and returns a decision per machine. Nothing in this function changes state, which
    is why it is safe to point at somebody else's tenant before anything is deployed.

    The plan is the same object the runbook acts on, so what this prints is what an armed run would
    do. Machines the rules leave alone are returned too, with the reason - a machine missing from a
    report is indistinguishable from a machine nobody looked at.

    Version one carries one rule: a machine in PowerState/stopped is powered off but still
    allocated on a host, and still billed for compute. Deallocating it interrupts nothing that is
    running. Schedules arrive in the next version.

    .PARAMETER SubscriptionId
    Subscriptions to search. Defaults to every subscription in the current context, which is what
    makes this one query rather than a loop.

    .PARAMETER ScheduleTag
    Tag key that opts a machine in. Defaults to PowerSchedule.

    .PARAMETER ExclusionTag
    Tag key that protects a machine from every rule. Defaults to PowerSchedule-Exclude.

    .PARAMETER IncludeUntagged
    Also plan actions for machines carrying no schedule tag. Off by default: a machine nobody has
    tagged is one nobody has decided about. Untagged stranded machines are reported either way,
    with the reason StrandedButNotOnboarded.

    .PARAMETER ActionableOnly
    Return only the machines an armed run would touch.

    .EXAMPLE
    # What would an armed run do right now, across every subscription in the current context?
    Get-VmPowerPlan | Format-Table Name, PowerState, Action, Reason

    .EXAMPLE
    # The money question, on a tenant where nothing is tagged yet: what is powered off and still billed?
    Get-VmPowerPlan | Where-Object Reason -match 'Stranded|StoppedNotDeallocated' | Format-Table Name, ResourceGroup, VmSize

    .EXAMPLE
    # Plan only what is onboarded, in two named subscriptions, then hand it to the executor to preview
    Get-VmPowerPlan -SubscriptionId '00000000-0000-0000-0000-000000000000' -ActionableOnly | Invoke-VmPowerPlan -WhatIf

    .INPUTS
    None

    .OUTPUTS
    AzureVMPowerManagement.VmPowerPlan

    .NOTES
    RequiredPermissions: Reader on every subscription in scope, or at a management group above
    them. Resource Graph returns only what the signed-in identity can already read, so a narrower
    assignment narrows the report rather than failing it.

    Prerequisites: PowerShell 7.2 or later and Az.Accounts. Resource Graph is called over REST
    rather than through Az.ResourceGraph, so that module is not needed.

    Writes: Nothing. This command reads Resource Graph and returns objects.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerPlan')]
    param(
        [Parameter()]
        [string[]]$SubscriptionId,

        [Parameter()]
        [string]$ScheduleTag,

        [Parameter()]
        [string]$ExclusionTag,

        [Parameter()]
        [switch]$IncludeUntagged,

        [Parameter()]
        [switch]$ActionableOnly
    )

    if (-not $ScheduleTag) { $ScheduleTag = $script:DefaultTag.Schedule }
    if (-not $ExclusionTag) { $ExclusionTag = $script:DefaultTag.Exclusion }

    $graph = @{ Query = Get-VmPowerInventoryQuery }
    if ($SubscriptionId) { $graph['SubscriptionId'] = $SubscriptionId }
    $machines = @(Invoke-VmPowerGraphQuery @graph)

    Write-Verbose "Resource Graph returned $($machines.Count) machine(s)."

    foreach ($machine in $machines) {
        $decision = Resolve-VmPowerAction -Machine $machine -ScheduleTag $ScheduleTag `
            -ExclusionTag $ExclusionTag -IncludeUntagged:$IncludeUntagged
        if ($ActionableOnly -and $decision.Action -eq 'None') { continue }
        $decision
    }
}
