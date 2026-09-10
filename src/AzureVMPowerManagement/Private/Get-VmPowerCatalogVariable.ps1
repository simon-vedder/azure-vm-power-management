function Get-VmPowerCatalogVariable {
    <#
    .SYNOPSIS
    Read one Automation variable and hand back the catalogue in it.

    .DESCRIPTION
    Over REST rather than through Az.Automation, for the same reason discovery avoids
    Az.ResourceGraph: the Automation PowerShell 7.2 runtime ships a fixed Az bundle and importing
    modules alongside it has broken assembly loading in the sandbox before. Az.Accounts is required
    anyway and carries Invoke-AzRestMethod.

    A variable that does not exist is not an error. Version one of a deployment has an empty custom
    catalogue by definition, and treating a 404 as a failure would mean the first run of every new
    deployment fails for the most ordinary reason there is.

    Automation stores a variable value as a string, and what that string contains depends on how it
    was written. Both shapes are handled: JSON that parses straight into a list, and JSON that
    parses into a string which is itself JSON. Guessing once and being wrong would mean an empty
    catalogue that looks like a configured one.

    .PARAMETER ResourceGroupName
    Resource group holding the Automation Account.

    .PARAMETER AutomationAccountName
    The Automation Account.

    .PARAMETER VariableName
    The variable to read.

    .PARAMETER SubscriptionId
    Subscription holding the account. Defaults to the current context.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$ResourceGroupName,

        [Parameter(Mandatory)]
        [string]$AutomationAccountName,

        [Parameter(Mandatory)]
        [string]$VariableName,

        [Parameter()]
        [string]$SubscriptionId
    )

    $subscription = if ($SubscriptionId) { $SubscriptionId } else { Resolve-VmPowerSubscription }
    $uri = ('/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/variables/{3}?api-version={4}' -f
        $subscription, $ResourceGroupName, $AutomationAccountName, $VariableName, $script:AutomationApiVersion)

    $response = Invoke-AzRestMethod -Path $uri -Method GET -ErrorAction Stop

    if ($response.StatusCode -eq 404) {
        Write-Verbose "Variable $VariableName does not exist yet; treating it as an empty catalogue."
        return @()
    }
    if ($response.StatusCode -ne 200) {
        throw "Reading the Automation variable $VariableName returned $($response.StatusCode): $($response.Content)"
    }

    $variable = $response.Content | ConvertFrom-Json
    if ($variable.properties.isEncrypted) {
        throw ("The Automation variable $VariableName is encrypted, so its value is not returned over ARM. " +
            'The catalogue is configuration rather than a secret, and the workbook reads it through the ' +
            'same API - see docs/decisions/0006. Recreate it unencrypted.')
    }

    $value = [string]$variable.properties.value
    if ([string]::IsNullOrWhiteSpace($value)) { return @() }

    $parsed = $value | ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [string]) { $parsed = $parsed | ConvertFrom-Json -ErrorAction Stop }

    @($parsed)
}
