function Resolve-VmPowerSubscription {
    <#
    .SYNOPSIS
    The subscription from the current Azure context, or a sentence saying there is not one.

    .DESCRIPTION
    `(Get-AzContext).Subscription.Id` on a session that has never signed in fails with "The property
    'Subscription' cannot be found on this object", which tells the reader nothing about what to do.
    Caught in CI on 2026-09-10, where no context exists and the message pointed at a property rather
    than at Connect-AzAccount.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    $context = Get-AzContext -ErrorAction SilentlyContinue
    $subscription = if ($context) { [string]$context.Subscription.Id } else { '' }
    if (-not $subscription) {
        throw 'No Azure subscription in the current context. Run Connect-AzAccount, or pass -SubscriptionId.'
    }
    $subscription
}
