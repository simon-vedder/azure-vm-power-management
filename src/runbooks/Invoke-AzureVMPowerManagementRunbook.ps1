<#
.SYNOPSIS
Run AzureVMPowerManagement from an Azure Automation runbook

.DESCRIPTION
Thin wrapper around the AzureVMPowerManagement module: signs in with the Automation Account's managed
identity, plans the work through the module and either reports it or performs it. The runbook knows
the operation; the module knows the rules. Keep this file free of rules.

It ships disarmed. -Armed defaults to false, so a deployed schedule discovers, decides and prints
everything while changing nothing. Read a week of that before arming it - see
docs/decisions/0004-eager-to-start-reluctant-to-stop.md.

Discovery reaches every subscription the managed identity can read in one Resource Graph call, so
-SubscriptionId is a narrowing option rather than a requirement. All optional flags are [bool]
instead of [switch] because the Automation "Start runbook" dialog cannot populate switch parameters.

.PARAMETER SubscriptionId
Narrow discovery to these subscriptions. Leave empty to plan across everything the identity reads.

.PARAMETER Armed
False, the default, plans and reports without touching a machine. True performs the plan.

.PARAMETER MaximumActions
Refuse the whole run if it would act on more machines than this. There is no safe default for
somebody else's estate, so the deployment sets it explicitly.

.PARAMETER MinimumDwellMinutes
Leave a machine alone if this runbook acted on it more recently than this.

.PARAMETER IncludeUntagged
Also act on machines carrying no schedule tag. Off by default: opt-in is the rule. Untagged machines
that are powered off and still billed are reported either way.

.PARAMETER ScheduleCatalog
The schedule catalogue as JSON. The deployment reads PM_ScheduleCatalog and
PM_ScheduleCatalogCustom and passes the merged result. Empty means only the stranded-machine rule
applies, which is a complete and useful run on its own.

.PARAMETER ScheduleTag
Tag key that opts a machine in. Empty uses the module's default, PowerSchedule.

.PARAMETER ExclusionTag
Tag key that protects a machine from every rule. Empty uses the module's default.

.PARAMETER ManagedIdentityClientId
Client ID of a user-assigned managed identity. Leave empty for the system-assigned identity.

.EXAMPLE
# What a deployed schedule does on day one: plan the whole estate, change nothing.
.\Invoke-AzureVMPowerManagementRunbook.ps1 -MaximumActions 50

.EXAMPLE
# Armed, limited to one subscription, refusing any run that would touch more than twenty machines.
.\Invoke-AzureVMPowerManagementRunbook.ps1 -SubscriptionId '00000000-0000-0000-0000-000000000000' -Armed $true -MaximumActions 20

.INPUTS
None

.OUTPUTS
AzureVMPowerManagement.VmPowerPlan when disarmed, AzureVMPowerManagement.VmPowerPlanResult when
armed, one per machine, plus a summary string.

.NOTES
Author:              Simon Vedder (simonvedder.com)
Version:             0.1.0
RequiredPermissions: Managed identity with Reader for discovery, plus the custom role from
                     deploy/main.bicep for the power actions, on the target scope.
Prerequisites:       Azure Automation PowerShell 7.2+ runtime; modules AzureVMPowerManagement,
                     Az.Accounts and Az.Compute.

.LINK
https://github.com/simon-vedder/azure-vm-power-management
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$SubscriptionId,

    [Parameter()]
    [bool]$Armed = $false,

    [Parameter(Mandatory)]
    [ValidateRange(1, 10000)]
    [int]$MaximumActions,

    [Parameter()]
    [ValidateRange(0, 1440)]
    [int]$MinimumDwellMinutes = 30,

    [Parameter()]
    [bool]$IncludeUntagged = $false,

    [Parameter()]
    [string]$ScheduleCatalog,

    [Parameter()]
    [string]$ScheduleTag,

    [Parameter()]
    [string]$ExclusionTag,

    [Parameter()]
    [string]$ManagedIdentityClientId
)

$ErrorActionPreference = 'Stop'

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module AzureVMPowerManagement -ErrorAction Stop

$connect = @{ Identity = $true; ErrorAction = 'Stop' }
if ($ManagedIdentityClientId) { $connect['AccountId'] = $ManagedIdentityClientId.Trim() }
$null = Connect-AzAccount @connect

# With roles in more than one subscription, Connect-AzAccount -Identity picks the first it sees as
# the context. Resource Graph does not care - it answers for everything the identity reads - but
# Stop-AzVM does, so the context is pinned per machine by resource group rather than assumed here.
$scope = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every readable subscription' }
Write-Output "Scope: $scope | Armed: $Armed | MaximumActions: $MaximumActions | Dwell: $MinimumDwellMinutes min"

# The catalogue is validated before it decides anything. A malformed entry that reached the rules
# would either throw halfway through a run or, worse, resolve to something nobody wrote.
$catalog = @()
if ($ScheduleCatalog) {
    $parsed = @($ScheduleCatalog | ConvertFrom-Json -ErrorAction Stop)
    $checked = @($parsed | Test-VmPowerSchedule -Detailed)
    $bad = @($checked | Where-Object { -not $_.Valid })
    if ($bad.Count) {
        throw ("The schedule catalogue has $($bad.Count) problem(s), so nothing was planned: " +
            (($bad | ForEach-Object { "$($_.Name): $($_.Problem)" }) -join ' | '))
    }
    $catalog = @($checked.Schedule)
    Write-Output "Catalogue: $($catalog.Count) schedule(s) - $(($catalog.Name | Sort-Object) -join ', ')"
}
else {
    Write-Output 'Catalogue: none. Only the stranded-machine rule applies.'
}

$planArgs = @{ IncludeUntagged = $IncludeUntagged }
if ($catalog.Count) { $planArgs['Schedule'] = $catalog }
if ($SubscriptionId) { $planArgs['SubscriptionId'] = $SubscriptionId }
if ($ScheduleTag) { $planArgs['ScheduleTag'] = $ScheduleTag }
if ($ExclusionTag) { $planArgs['ExclusionTag'] = $ExclusionTag }

$plan = @(Get-VmPowerPlan @planArgs)
$actionable = @($plan | Where-Object { $_.Action -ne 'None' -and -not $_.Protected })
Write-Output "Planned: $($plan.Count) machine(s), $($actionable.Count) actionable"

$summary = @{}
function Add-Summary {
    param([string]$Key)
    if ($summary.ContainsKey($Key)) { $summary[$Key]++ } else { $summary[$Key] = 1 }
}

if (-not $Armed) {
    # Disarmed is not a different code path: the same plan is printed instead of performed, so what
    # a first week reports is exactly what arming it would have done.
    foreach ($item in $plan) {
        Write-Output "[$($item.Name)] $($item.Action) - $($item.Reason): $($item.Explanation)"
        Add-Summary $item.Reason
        $item
    }
}
else {
    foreach ($result in ($plan | Invoke-VmPowerPlan -MaximumActions $MaximumActions -MinimumDwellMinutes $MinimumDwellMinutes -Confirm:$false)) {
        Write-Output "[$($result.Name)] $($result.Action) - $($result.Status): $($result.Detail)"
        Add-Summary $result.Status
        $result
    }
}

Write-Output ('Summary: ' + $(if ($summary.Count) {
            ($summary.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        }
        else { 'nothing to do' }))
