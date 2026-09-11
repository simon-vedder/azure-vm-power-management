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

    # A catalogue entry that is itself a collection serialises as a nested array, and the reader
    # then sees a schedule with no name. That reached a real Automation Account once, on
    # 2026-09-10, and the read side only said "name '' is not usable" - true, and useless. Refusing
    # here names the entry instead.
    $flat = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in @($Catalog)) {
        if ($null -eq $entry) { continue }
        # A dictionary is IEnumerable too, and the stored shape is one. What this guard is for is
        # an array arriving where a schedule should be, which is what produces the nested array
        # nothing can read back.
        if ($entry -isnot [System.Collections.IDictionary] -and $entry -is [System.Collections.IEnumerable] -and $entry -isnot [string]) {
            throw ("A catalogue entry is a collection rather than a schedule, so the value would be " +
                'a nested array that nothing can read back. This is a bug in the caller, not in the ' +
                'catalogue: pass one schedule per entry.')
        }
        $flat.Add($entry)
    }

    # Written in the camelCase shape the deployment uses, not the PascalCase of the expanded object.
    # Every reader in this module is case-insensitive, so the difference was invisible here - and
    # fatal in the runbook, where Get-AutomationVariable returns a JObject that indexes
    # case-sensitively and found nothing under 'name'. Converted here rather than in each caller,
    # because this is the only function that writes a catalogue and there is no second shape to
    # keep in step. See ConvertTo-VmPowerStoredSchedule.
    $shaped = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $flat) { $shaped.Add((ConvertTo-VmPowerStoredSchedule -Schedule $entry)) }
    $flat = $shaped

    $subscription = if ($SubscriptionId) { $SubscriptionId } else { Resolve-VmPowerSubscription }
    $uri = ('/subscriptions/{0}/resourceGroups/{1}/providers/Microsoft.Automation/automationAccounts/{2}/variables/{3}?api-version={4}' -f
        $subscription, $ResourceGroupName, $AutomationAccountName, $VariableName, $script:AutomationApiVersion)

    $json = ConvertTo-Json -InputObject @($flat.ToArray()) -Depth 8 -Compress

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
    Write-Verbose "Wrote $($flat.Count) schedule(s), $($json.Length) characters, to $VariableName."
}
