function Invoke-VmPowerGraphQuery {
    <#
    .SYNOPSIS
    Run one Resource Graph query and return every page of it.

    .DESCRIPTION
    Calls the Resource Graph REST API through Invoke-AzRestMethod rather than Search-AzGraph, which
    means Az.ResourceGraph is not a dependency. That matters in Azure Automation: the PowerShell
    7.2 runtime ships a fixed Az bundle, and importing Az modules alongside it has broken assembly
    loading in the sandbox before. Az.Accounts is already required for signing in, and it carries
    Invoke-AzRestMethod, so this costs nothing.

    Omitting the subscription list is deliberate. Resource Graph then answers for every subscription
    the signed-in identity can read - verified on 2026-09-10 against a tenant with two - which is
    what makes discovery one call rather than a loop with a context switch in it.

    Paging is not optional. Resource Graph returns at most 1000 rows per page, and a plan that
    silently stops at the first page is worse than no plan.

    .PARAMETER Query
    The KQL query.

    .PARAMETER SubscriptionId
    Limit the query to these subscriptions. Omit for every subscription the identity can read.

    .PARAMETER PageSize
    Rows per page. The service caps this at 1000.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter()]
        [string[]]$SubscriptionId,

        [Parameter()]
        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    $uri = 'https://management.azure.com/providers/Microsoft.ResourceGraph/resources?api-version=2022-10-01'
    $rows = [System.Collections.Generic.List[object]]::new()
    $skipToken = $null
    $page = 0

    do {
        $body = [ordered]@{ query = $Query; options = [ordered]@{ '$top' = $PageSize } }
        if ($SubscriptionId) { $body['subscriptions'] = @($SubscriptionId) }
        if ($skipToken) { $body.options['$skipToken'] = $skipToken }

        $response = Invoke-AzRestMethod -Uri $uri -Method POST -Payload ($body | ConvertTo-Json -Depth 5 -Compress) -ErrorAction Stop
        if ($response.StatusCode -ne 200) {
            throw "Resource Graph returned $($response.StatusCode): $($response.Content)"
        }

        $result = $response.Content | ConvertFrom-Json
        foreach ($row in @($result.data)) { $rows.Add($row) }

        $skipToken = if ($result.PSObject.Properties.Name -contains '$skipToken') { $result.'$skipToken' } else { $null }
        $page++
        Write-Verbose "Resource Graph page $page returned $(@($result.data).Count) row(s); total so far $($rows.Count) of $($result.totalRecords)."
    } while ($skipToken)

    , $rows.ToArray()
}
