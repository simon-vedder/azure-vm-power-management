<#
.SYNOPSIS
Drive the runbook end to end against a simulated estate and report what it did as JSON

.DESCRIPTION
The module has unit tests and the deployment has a drift check. Between them sits the runbook, and
nothing covered it: it is the only file that reads settings, merges the catalogue, calls the plan,
calls the executor and writes back what it did. Every defect this script has found so far was
invisible to the 160-odd tests next to it, because each half was correct on its own.

Nothing here touches Azure. Resource Graph, the Az power cmdlets, the Az context and the Automation
asset store are stubbed in the global scope, which is why this runs in its own process rather than
inside the Pester session: a global Stop-AzVM would follow every other test file around.

The estate is deliberately awkward. Two subscriptions hold a machine with the same name in a
resource group with the same name, which is what dev and test estates actually look like and what
makes a missing context switch deallocate the wrong machine rather than fail.

.PARAMETER RepositoryRoot
Root of the repository. Defaults to two levels above this script.

.PARAMETER OutputPath
Write the JSON here instead of to the pipeline. Use it from a test: -WhatIf messages are written
straight to the host and cannot be redirected, so anything reading stdout gets them mixed in.

.EXAMPLE
# Read it as a person
pwsh -File tests/orchestrator/Invoke-OrchestratorScenarios.ps1 -Verbose

.EXAMPLE
# What Orchestrator.Tests.ps1 does
pwsh -NoProfile -File tests/orchestrator/Invoke-OrchestratorScenarios.ps1 -OutputPath ./scenarios.json

.OUTPUTS
One JSON object describing what each scenario did.

.NOTES
Author:              Simon Vedder (simonvedder.com)
RequiredPermissions: None. Nothing here reaches a network.
Prerequisites:       PowerShell 7.2 or later, Az.Accounts and Az.Compute installed (the module
                     manifest requires them; they are never called).
#>
# The globals are the point: a stub reached from another script file resolves $script: against that
# file, so the estate and the asset store have to live in the global scope for the runbook to see
# them. The stubs stand in for cmdlets, so their parameters look unused and their verbs look
# state-changing. All deliberate, all confined to this file, which is why it runs in its own process.
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Stubs must be reachable from the runbook and the module, which are separate script and module scopes.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', '', Justification = 'Stubs mirror the real cmdlet signatures so parameter binding behaves the same.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Stubs stand in for cmdlets that have their own ShouldProcess; adding another would change what is being tested.')]
[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..' '..')),

    [Parameter()]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$env:PSModulePath = (Join-Path $RepositoryRoot 'src') + [IO.Path]::PathSeparator + $env:PSModulePath
$runbook = Join-Path $RepositoryRoot 'src' 'runbooks' 'Invoke-AzureVMPowerManagementRunbook.ps1'

$subA = '11111111-1111-1111-1111-111111111111'
$subB = '22222222-2222-2222-2222-222222222222'
function New-Id { param($Sub, $Name) "/subscriptions/$Sub/resourceGroups/rg-shared/providers/Microsoft.Compute/virtualMachines/$Name" }

# Global, not script-scoped: a global function called from another script file resolves $script:
# against that file, not against this one. Which is its own small trap, and cost an hour.
$global:vms = [ordered]@{
    (New-Id $subA 'vm-app')  = @{ sub = $subA; name = 'vm-app'; power = 'PowerState/stopped'; tags = @{ PowerSchedule = 'office-hours-ch' } }
    (New-Id $subB 'vm-app')  = @{ sub = $subB; name = 'vm-app'; power = 'PowerState/stopped'; tags = @{ PowerSchedule = 'office-hours-ch' } }
    (New-Id $subA 'vm-keep') = @{ sub = $subA; name = 'vm-keep'; power = 'PowerState/running'; tags = @{ PowerSchedule = 'always-on' } }
}
$global:context = $subA
$global:stops = [System.Collections.Generic.List[string]]::new()

# Exactly what deploy/modules/automation.bicep writes, Windows time zone ids and all.
$global:assets = @{
    PM_Armed               = $false
    PM_MaximumActions      = 25
    PM_MinimumDwellMinutes = 30
    PM_ScheduleTag         = 'PowerSchedule'
    PM_ExclusionTag        = 'PowerSchedule-Exclude'
    PM_LastActionAt        = '{}'
    PM_ScheduleCatalog     = (ConvertTo-Json -Compress -Depth 8 -InputObject @(
            @{ name = 'office-hours-ch'; timeZone = 'W. Europe Standard Time'; weekdays = '07:30-18:30'; minimumDwellMinutes = 45 }
            @{ name = 'always-on'; timeZone = 'UTC'; actions = @(@{ action = 'Start'; at = '06:00'; weekDays = 'All' }); minimumDwellMinutes = 30 }
        ))
}

function global:Get-AutomationVariable {
    param([string]$Name)
    if ($global:assets.ContainsKey($Name)) { $global:assets[$Name] } else { throw "The variable $Name was not found." }
}
function global:Set-AutomationVariable { param([string]$Name, $Value) $global:assets[$Name] = $Value }
function global:Connect-AzAccount { param() [pscustomobject]@{ Context = 'stub' } }
function global:Get-AzContext { [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:context } } }
function global:Set-AzContext {
    param($Subscription, $Scope)
    $global:context = "$Subscription"
    [pscustomobject]@{ Subscription = [pscustomobject]@{ Id = $global:context } }
}

function global:Stop-AzVM {
    param([string]$ResourceGroupName, [string]$Name, [switch]$Force)
    # The whole reason this file exists. An Az power cmdlet acts in the current context and takes
    # no subscription, so this stub resolves the machine the way Azure would: from the context.
    $id = "/subscriptions/$global:context/resourceGroups/$ResourceGroupName/providers/Microsoft.Compute/virtualMachines/$Name"
    if (-not $global:vms.Contains($id)) { throw "ResourceNotFound: the resource '$Name' under resource group '$ResourceGroupName' was not found." }
    $global:vms[$id].power = 'PowerState/deallocated'
    $global:stops.Add($id)
}
function global:Start-AzVM { param([string]$ResourceGroupName, [string]$Name) }

function global:Invoke-AzRestMethod {
    param($Uri, $Method, $Payload, $Path)
    $rows = foreach ($id in $global:vms.Keys) {
        $vm = $global:vms[$id]
        @{
            id = $id; name = $vm.name; powerState = $vm.power; location = 'westeurope'
            resourceGroup = 'rg-shared'; subscriptionId = $vm.sub; vmSize = 'Standard_B1s'; tags = $vm.tags
        }
    }
    [pscustomobject]@{
        StatusCode = 200
        Content    = (ConvertTo-Json -Depth 8 -InputObject @{ data = @($rows); totalRecords = @($rows).Count })
    }
}

function Invoke-Scenario {
    param([string]$Name, [hashtable]$Splat = @{ MaximumActions = 25 })
    $before = $global:stops.Count
    $lines = [System.Collections.Generic.List[string]]::new()
    $records = [System.Collections.Generic.List[object]]::new()
    $refused = ''
    try {
        foreach ($item in (& $runbook @Splat)) {
            if ($item -isnot [string]) { continue }
            if ($item.StartsWith('PMREC ')) { $records.Add(($item.Substring(6) | ConvertFrom-Json)); continue }
            $lines.Add($item)
        }
    }
    catch { $refused = $_.Exception.Message }

    Write-Verbose "--- $Name ---"
    $lines | ForEach-Object { Write-Verbose "  $_" }
    if ($refused) { Write-Verbose "  refused: $refused" }

    [ordered]@{
        name        = $Name
        stops       = $global:stops.Count - $before
        stoppedIds  = @($global:stops | Select-Object -Skip $before)
        refused     = $refused
        records     = @($records | ForEach-Object { [ordered]@{ vm = $_.vm; sub = $_.sub; action = $_.action; status = $_.status } })
        lines       = @($lines)
        lastActionAt = [string]$global:assets.PM_LastActionAt
    }
}

$results = [System.Collections.Generic.List[object]]::new()

$results.Add((Invoke-Scenario 'disarmed'))

$global:assets.PM_Armed = $true
$results.Add((Invoke-Scenario 'armed across two subscriptions'))

# Somebody shuts the sub-a machine down again, minutes later. The schedule's own 45 minute dwell
# should hold it, not the run-wide 30.
$global:vms[(New-Id $subA 'vm-app')].power = 'PowerState/stopped'
$results.Add((Invoke-Scenario 'inside the dwell window'))

# The same machine once the memory has aged past the dwell.
$aged = @{}
foreach ($p in (($global:assets.PM_LastActionAt | ConvertFrom-Json).PSObject.Properties)) {
    $aged[$p.Name] = ([datetime]::UtcNow.AddMinutes(-50)).ToString('o')
}
$global:assets.PM_LastActionAt = (ConvertTo-Json -InputObject $aged -Compress)
$results.Add((Invoke-Scenario 'past the dwell window'))

# A blast radius set too low has to fail the disarmed run, or a first week cannot warn about it.
$global:assets.PM_Armed = $false
$global:assets.PM_LastActionAt = '{}'
foreach ($id in $global:vms.Keys) { $global:vms[$id].power = 'PowerState/stopped' }
$results.Add((Invoke-Scenario 'blast radius, disarmed' @{ MaximumActions = 1 }))

# An unreadable memory must stop the run rather than quietly stand the guard down.
$global:assets.PM_Armed = $true
$global:assets.PM_LastActionAt = 'not json at all'
$results.Add((Invoke-Scenario 'corrupt dwell store' @{ MaximumActions = 25 }))

$json = ConvertTo-Json -InputObject @{ scenarios = @($results) } -Depth 8
if ($OutputPath) { Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8 } else { $json }
