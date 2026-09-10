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
somebody else's estate: without this and without the Automation variable PM_MaximumActions, the
run refuses rather than picking one.

.PARAMETER MinimumDwellMinutes
Leave a machine alone if this runbook acted on it more recently than this.

.PARAMETER IncludeUntagged
Also act on machines carrying no schedule tag. Off by default: opt-in is the rule. Untagged machines
that are powered off and still billed are reported either way.

.PARAMETER ScheduleCatalog
The schedule catalogue as JSON. Empty reads PM_ScheduleCatalog and PM_ScheduleCatalogCustom from
the Automation Account and merges them, custom winning on a name collision. No catalogue at all
means only the stranded-machine rule applies, which is a complete and useful run on its own.

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

    [Parameter()]
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

# Every operable setting comes from an Automation variable unless the caller passed it explicitly.
# Job schedule parameters are immutable once the link exists - Automation ignores a PUT on a link
# that is already there and keeps the old parameters, reporting success. Arming a deployment would
# then mean deleting the link and redeploying. Variables are editable in the portal instead.
function Get-Setting {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()]$Fallback = $null
    )
    if (-not (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue)) { return $Fallback }
    try {
        $value = Get-AutomationVariable -Name $Name -ErrorAction Stop
        if ($null -eq $value -or "$value" -eq '') { return $Fallback }
        return $value
    }
    catch { return $Fallback }
}

# [bool]'false' is $true. Every non-empty string is. Whether Get-AutomationVariable hands back a
# real boolean or the text depends on how the value was stored, so a cast here would arm a
# deployment whose PM_Armed says false - the exact failure every guard in this tool exists to
# prevent. Parsed explicitly, and anything unrecognised stops the run: a controller that cannot
# tell whether it is armed has no business acting.
function ConvertTo-SettingBool {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()]$Value,
        [Parameter(Mandatory)][bool]$Fallback
    )
    if ($null -eq $Value) { return $Fallback }
    if ($Value -is [bool]) { return $Value }
    $text = "$Value".Trim().ToLowerInvariant()
    if (-not $text) { return $Fallback }
    switch ($text) {
        'true' { return $true }
        '1' { return $true }
        'yes' { return $true }
        'false' { return $false }
        '0' { return $false }
        'no' { return $false }
    }
    throw "The Automation variable $Name holds '$Value', which is not a yes or a no. Set it to true or false."
}

function ConvertTo-SettingInt {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter()][AllowNull()]$Value,
        [Parameter(Mandatory)][int]$Fallback
    )
    if ($null -eq $Value -or "$Value".Trim() -eq '') { return $Fallback }
    $number = 0
    if (-not [int]::TryParse("$Value".Trim(), [ref]$number)) {
        throw "The Automation variable $Name holds '$Value', which is not a whole number."
    }
    $number
}

if (-not $PSBoundParameters.ContainsKey('Armed')) { $Armed = ConvertTo-SettingBool -Name 'PM_Armed' -Value (Get-Setting -Name 'PM_Armed') -Fallback $false }
if (-not $PSBoundParameters.ContainsKey('MinimumDwellMinutes')) { $MinimumDwellMinutes = ConvertTo-SettingInt -Name 'PM_MinimumDwellMinutes' -Value (Get-Setting -Name 'PM_MinimumDwellMinutes') -Fallback 30 }
if (-not $PSBoundParameters.ContainsKey('IncludeUntagged')) { $IncludeUntagged = ConvertTo-SettingBool -Name 'PM_IncludeUntagged' -Value (Get-Setting -Name 'PM_IncludeUntagged') -Fallback $false }
if (-not $PSBoundParameters.ContainsKey('ScheduleTag')) { $ScheduleTag = [string](Get-Setting -Name 'PM_ScheduleTag' -Fallback '') }
if (-not $PSBoundParameters.ContainsKey('ExclusionTag')) { $ExclusionTag = [string](Get-Setting -Name 'PM_ExclusionTag' -Fallback '') }
if (-not $PSBoundParameters.ContainsKey('SubscriptionId')) {
    $fromVariable = [string](Get-Setting -Name 'PM_SubscriptionId' -Fallback '')
    if ($fromVariable) { $SubscriptionId = @($fromVariable -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
}
if (-not $PSBoundParameters.ContainsKey('MaximumActions')) {
    $MaximumActions = ConvertTo-SettingInt -Name 'PM_MaximumActions' -Value (Get-Setting -Name 'PM_MaximumActions') -Fallback 0
}
if ($MaximumActions -lt 1) {
    throw ('No blast radius is set. Give -MaximumActions, or set the Automation variable ' +
        'PM_MaximumActions. There is no default that is right for somebody else''s estate, so this ' +
        'refuses rather than picking one - see docs/decisions/0004.')
}

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
# The catalogue is two variables: the deployment owns the first and overwrites it, nothing but
# Set-VmPowerSchedule writes the second, and a custom entry wins on a name collision (ADR 0005).
# Read through Get-AutomationVariable rather than over ARM, so the identity needs no permission on
# its own Automation Account.
# The same variable has two shapes depending on how it is read. Over ARM, properties.value is the
# raw JSON text - which is why Get-VmPowerSchedule parses it. Get-AutomationVariable deserialises
# it first, so here a JSON array arrives as objects. Casting that to a string and parsing it fails
# with "Additional text encountered after finished reading JSON content", which is what the first
# real runbook job did on 2026-09-10. Both shapes are accepted.
function ConvertTo-CatalogArray {
    param([Parameter()][AllowNull()]$Value)
    if ($null -eq $Value) { return @() }
    if ($Value -is [string]) {
        if (-not $Value.Trim()) { return @() }
        return @($Value | ConvertFrom-Json -ErrorAction Stop)
    }
    @($Value)
}

if (-not $ScheduleCatalog) {
    $merged = [ordered]@{}
    foreach ($variableName in 'PM_ScheduleCatalog', 'PM_ScheduleCatalogCustom') {
        foreach ($entry in (ConvertTo-CatalogArray -Value (Get-Setting -Name $variableName))) {
            if ($null -eq $entry) { continue }
            $merged[[string]$entry.name] = $entry
        }
    }
    if ($merged.Count) { $ScheduleCatalog = ConvertTo-Json -InputObject @($merged.Values) -Depth 8 -Compress }
}

$catalog = @()
if ($ScheduleCatalog) {
    $parsed = ConvertTo-CatalogArray -Value $ScheduleCatalog
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
