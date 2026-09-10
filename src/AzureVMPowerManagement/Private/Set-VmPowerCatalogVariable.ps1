function Set-VmPowerCatalogVariable {
    <#
    .SYNOPSIS
    Write a catalogue into one Automation variable.

    .DESCRIPTION
    Only ever called for the custom variable. The deployment owns PM_ScheduleCatalog and overwrites
    it on every run; nothing in this module writes there, which is what stops a redeployment eating
    somebody's work - see docs/decisions/0005.

    The value is written as JSON and read back with ConvertFrom-Json, so what goes in is what comes
    out. Never encrypted: the workbook reads this variable over ARM, and an encrypted variable does
    not return its value there.

    .PARAMETER ResourceGroupName
    Resource group holding the Automation Account.

    .PARAMETER AutomationAccountName
    The Automation Account.

    .PARAMETER VariableName
    The variable to write.

    .PARAMETER Catalog
    The schedules to store.

    .PARAMETER SubscriptionId
    Subscription holding the account. Defaults to the current context.
    #>
    [CmdletBinding()]
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Private helper. The confirmation belongs at the public boundary, in Set-VmPowerSchedule and Remove-VmPowerSchedule, where the caller can see which schedules are involved. Asking twice for one action is worse than asking once in the right place.')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$AutomationAccountName,

        [Parameter(Mandatory)]
        [string]$VariableName,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Catalog,

        [Parameter()]
        [string]$SubscriptionId
    )

    $subscription = if ($SubscriptionId) { $SubscriptionId } else { (Get-AzContext -ErrorAction Stop).Subscription.Id }
    $uri = ('/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/variables/{3}?api-version={4}' -f
        $subscription, $ResourceGroupName, $AutomationAccountName, $VariableName, $script:AutomationApiVersion)

    # An array of one collapses to a bare object without the comma, and the reader would then get a
    # schedule where it expects a list.
    $json = ConvertTo-Json -InputObject @($Catalog) -Depth 8 -Compress

    $limit = 1048576
    if ($json.Length -gt $limit) {
        throw "The catalogue is $($json.Length) characters and an Automation variable holds $limit. That is thousands of schedules, so this is far more likely to be a loop than a catalogue."
    }

    $body = @{
        name       = $VariableName
        properties = @{
            value       = $json
            isEncrypted = $false
            description = 'Schedules added with Set-VmPowerSchedule. The deployment never writes here.'
        }
    } | ConvertTo-Json -Depth 8 -Compress

    $response = Invoke-AzRestMethod -Path $uri -Method PUT -Payload $body -ErrorAction Stop
    if ($response.StatusCode -notin 200, 201) {
        throw "Writing the Automation variable $VariableName returned $($response.StatusCode): $($response.Content)"
    }
    Write-Verbose "Wrote $(@($Catalog).Count) schedule(s), $($json.Length) characters, to $VariableName."
}
