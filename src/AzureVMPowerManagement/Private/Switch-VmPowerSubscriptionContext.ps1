function Switch-VmPowerSubscriptionContext {
    <#
    .SYNOPSIS
    Point the Az context at the subscription a machine lives in, before acting on it.

    .DESCRIPTION
    Discovery and execution do not have the same reach, and that asymmetry is easy to miss. One
    Resource Graph query answers for every subscription the identity can read. Stop-AzVM and
    Start-AzVM have no -SubscriptionId at all: they act in whatever subscription the current context
    names, and Connect-AzAccount -Identity picks the first one it sees.

    Two things go wrong without this. A plan spanning three subscriptions fails on two of them with
    a resource-not-found that names a machine the report just listed. And where a resource group
    name and a machine name are reused across subscriptions - dev/test estates do this constantly -
    the call resolves against the wrong subscription and deallocates the wrong machine.

    The context is changed only when it has to be, so a single-subscription estate never pays for a
    switch it does not need. Scope is Process: an Automation sandbox is thrown away after the job
    and has no profile worth writing to disk.

    .PARAMETER SubscriptionId
    Subscription the machine lives in. An empty value leaves the context alone, which is what a
    plan built from a fixture rather than from Resource Graph produces.
    #>
    [CmdletBinding()]
    [OutputType([void])]
    param(
        [Parameter()]
        [AllowEmptyString()]
        [string]$SubscriptionId
    )

    if ([string]::IsNullOrWhiteSpace($SubscriptionId)) { return }

    $context = Get-AzContext
    if ($context -and $context.Subscription -and $context.Subscription.Id -eq $SubscriptionId) { return }

    try {
        $null = Set-AzContext -Subscription $SubscriptionId -Scope Process -Confirm:$false -ErrorAction Stop -WarningAction SilentlyContinue
    }
    catch {
        # Reported against the machine rather than thrown out of the run: one unreachable
        # subscription is not a reason to abandon the ones that are reachable.
        throw ("Could not switch to subscription $SubscriptionId, so this machine was not touched. " +
            'Resource Graph found it with read access alone; acting on it needs the operator role ' +
            "in that subscription as well. $($_.Exception.Message)")
    }

    Write-Verbose "Context is now subscription $SubscriptionId."
}
