function Get-VmPowerInventoryQuery {
    <#
    .SYNOPSIS
    The Resource Graph query that finds every machine this tool might act on.

    .DESCRIPTION
    One query for the whole estate. Resource Graph reaches every subscription the caller can read
    in a single call, which is why discovery does not loop over subscriptions or switch context.

    Power state is read from properties.extended.instanceView.powerState.code rather than
    .displayStatus. Microsoft's own FinOps sample uses displayStatus, which carries values like
    'VM deallocated' - a string meant for a portal blade, not for a comparison in a runbook. The
    code form ('PowerState/deallocated') is the stable one.

    The query deliberately does not filter. A machine that is running, or whose power state cannot
    be read at all, still belongs in the report: the caller decides what to do about it, and a
    machine missing from a report is indistinguishable from a machine nobody looked at.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    @'
resources
| where type =~ 'microsoft.compute/virtualmachines'
| extend powerState = tostring(properties.extended.instanceView.powerState.code)
| project
    id,
    name,
    powerState,
    location,
    resourceGroup,
    subscriptionId,
    vmSize = tostring(properties.hardwareProfile.vmSize),
    tags
| order by id asc
'@
}
