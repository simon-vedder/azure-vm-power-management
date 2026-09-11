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

Disarmed is the same code path with -WhatIf on it, not a second one. Every guard is evaluated, so a
blast radius set too low fails the job in week one rather than at the moment somebody arms it. A
disarmed job that fails on "more than the N allowed" is the tool telling you the number is wrong
while nothing is at stake.

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
Leave a machine alone if this runbook acted on it more recently than this. The memory lives in the
Automation variable PM_LastActionAt, which this runbook writes at the end of an armed run - without
it there is nothing to compare against and the guard cannot fire. Zero switches the check off. A
schedule carrying its own minimumDwellMinutes can ask for longer, never shorter.

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

# Marker the workbook keys on. Changing it silently empties every panel, so it lives in one place
# and is quoted in deploy/workbook.json rather than retyped there.
$script:RecordPrefix = 'PMREC'
$runId = [guid]::NewGuid().ToString()
$runStarted = [datetime]::UtcNow.ToString('o')

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

# The same read, for the values that are not scalars. It needs its own function because the two
# cannot be served by one: PowerShell unrolls a collection on its way out of a function, and
# Automation hands a JSON array back as a Newtonsoft JArray - so a catalogue of exactly one
# schedule arrived at the caller as that schedule, and one level further as that schedule's fields.
# Two or more schedules hid it completely, which is how it survived a real lab and a real armed run.
#
# -NoEnumerate fixes that and is not transparent: applied to a string it wraps it in a collection,
# which is why Get-Setting above must not use it. Structured here, scalar there, and no shared
# cleverness between them.
function Get-StructuredSetting {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Get-Command -Name Get-AutomationVariable -ErrorAction SilentlyContinue)) { return }
    try { $value = Get-AutomationVariable -Name $Name -ErrorAction Stop }
    catch { return }
    if ($null -eq $value) { return }

    # Only what would otherwise unroll. -NoEnumerate applied to a string wraps it in a collection
    # of one, which is a different bug in the same place.
    if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
        Write-Output $value -NoEnumerate
        return
    }
    $value
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
# Stop-AzVM does, and takes no subscription of its own. The module pins the context per machine
# from the subscription on the plan, in Switch-VmPowerSubscriptionContext; this comment used to
# claim that happened here, and it happened nowhere.
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

    if ($null -eq $Value) { return , @() }

    if ($Value -is [string]) {
        if (-not $Value.Trim()) { return , @() }
        $Value = $Value | ConvertFrom-Json -ErrorAction Stop
    }

    # Everything here is enumerable twice over: a JArray yields JObjects and a JObject yields
    # JProperties. PowerShell unrolls a collection on its way out of a function and cannot tell
    # which level was meant, so a catalogue of exactly one schedule arrived here already collapsed
    # into that schedule - and enumerating it again produced its fields. Two JProperty objects
    # where one schedule should have been, and a run that died on "Expand-VmPowerSchedule was
    # given a collection". Two or more schedules hid it completely, which is why it survived a
    # real lab and a real armed run.
    #
    # So the level is decided by what the thing IS, not by whether it can be enumerated: a JObject
    # is one schedule, whatever PowerShell thinks of its contents.
    $items = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $Value -and $Value.GetType().FullName -eq 'Newtonsoft.Json.Linq.JObject') {
        $items.Add($Value)
    }
    elseif ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string] -and
        $Value -isnot [System.Collections.IDictionary]) {
        foreach ($item in $Value) { $items.Add($item) }
    }
    else {
        $items.Add($Value)
    }

    # The comma is load-bearing in the other direction: without it the array is unrolled on the way
    # out and a single entry is enumerated all over again by the caller. Callers assign the result
    # and must not wrap it in @(), which would put the array inside another array.
    , $items.ToArray()
}

# PM_LastActionAt is this runbook's memory of what it touched and when. It is the whole of the
# dwell guard: with no memory there is nothing to compare against, and -MinimumDwellMinutes is a
# number in a help file. Same two shapes as the catalogue - text over ARM, an object through
# Get-AutomationVariable.
function ConvertTo-ActionMemory {
    param([Parameter()][AllowNull()]$Value)

    $memory = @{}
    if ($null -eq $Value) { return $memory }

    $object = $Value
    if ($Value -is [string]) {
        if (-not $Value.Trim()) { return $memory }
        try { $object = $Value | ConvertFrom-Json -ErrorAction Stop }
        catch {
            # Not swallowed. Treating an unreadable memory as an empty one stands the guard down
            # without saying so, and the fix is one edit.
            throw ("The Automation variable PM_LastActionAt does not hold readable JSON, so the " +
                'dwell guard has nothing to work from. Set it to {} to start again. ' +
                $_.Exception.Message)
        }
    }

    if ($object -is [System.Collections.IDictionary]) {
        foreach ($key in @($object.Keys)) { $memory[[string]$key] = ConvertTo-MemoryStamp -Value $object[$key] }
        return $memory
    }

    # JProperty objects, either straight from a JObject or already unrolled into an array on the
    # way here. A JObject exposes one nameless PowerShell property and nothing else, so without
    # this the memory came back as a single entry under an empty key: the count looked plausible
    # and the dwell guard matched nothing.
    $jsonProperties = @($object | Where-Object {
            $null -ne $_ -and $_.GetType().FullName -eq 'Newtonsoft.Json.Linq.JProperty'
        })
    if ($jsonProperties.Count) {
        foreach ($item in $jsonProperties) { $memory[[string]$item.Name] = ConvertTo-MemoryStamp -Value $item.Value }
        return $memory
    }

    foreach ($property in @($object.PSObject.Properties)) { $memory[$property.Name] = ConvertTo-MemoryStamp -Value $property.Value }
    $memory
}

# ConvertFrom-Json does not hand back the string that went in. It recognises an ISO-8601 value and
# returns a DateTime, correctly zoned - and then [string] on that DateTime renders it in the short
# invariant format, without the Z and without the seconds' fraction. The zone is gone, Kind becomes
# Unspecified, and every reader downstream is free to guess local. That guess moved the dwell window
# by the local offset and pruned a store that was seconds old; found on 2026-09-10 by running the
# runbook end to end rather than by any unit test. Formatted explicitly here so the round trip is
# lossless whichever shape the variable arrived in.
function ConvertTo-MemoryStamp {
    param([Parameter()][AllowNull()]$Value)

    # One layer down, the same zone loss: a JProperty hands back a JValue, and casting that to a
    # string renders the DateTime inside it in the short invariant form, without the Z.
    if ($null -ne $Value -and $Value.GetType().FullName -like 'Newtonsoft.Json.Linq.J*' -and
        $Value.PSObject.Properties['Value']) {
        $Value = $Value.Value
    }

    if ($Value -is [datetime]) { return ([datetime]$Value).ToUniversalTime().ToString('o') }
    [string]$Value
}

# Written back through the sandbox's own asset cmdlet rather than over ARM, so the identity needs
# no permission on its own Automation Account. Set-AutomationVariable cannot create a variable, so
# the deployment ships PM_LastActionAt with {} in it.
function Save-ActionMemory {
    param(
        [Parameter(Mandatory)][hashtable]$Memory,
        [Parameter(Mandatory)][int]$KeepMinutes
    )

    # An entry older than the longest dwell in play can never change a decision again, so the
    # variable stays roughly the size of one busy day rather than growing for the life of the
    # deployment. The cap is the backstop: an Automation variable holds a megabyte.
    $cutoff = [datetime]::UtcNow.AddMinutes(-$KeepMinutes)
    $kept = [ordered]@{}
    foreach ($entry in ($Memory.GetEnumerator() | Sort-Object { $_.Value } -Descending)) {
        if ($kept.Count -ge 4000) { break }
        $when = [datetime]::MinValue
        if (-not [datetime]::TryParse($entry.Value, [cultureinfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::RoundtripKind, [ref]$when)) { continue }
        # Unspecified means UTC here, for the same reason the module reads it that way: everything
        # that writes this store writes UTC, and assuming local silently ages every entry by the
        # offset - which on a machine an hour ahead deletes a store that was written seconds ago.
        if ($when.Kind -eq [System.DateTimeKind]::Unspecified) {
            $when = [datetime]::SpecifyKind($when, [System.DateTimeKind]::Utc)
        }
        if ($when.ToUniversalTime() -lt $cutoff) { continue }
        $kept[$entry.Key] = $entry.Value
    }

    if (-not (Get-Command -Name Set-AutomationVariable -ErrorAction SilentlyContinue)) {
        Write-Output ('Dwell: nothing remembered. Set-AutomationVariable is not available here, so ' +
            'the next run has no memory and the dwell guard will not fire.')
        return
    }

    try {
        Set-AutomationVariable -Name 'PM_LastActionAt' -Value (ConvertTo-Json -InputObject $kept -Depth 2 -Compress)
        Write-Output "Dwell: remembered $($kept.Count) machine(s) in PM_LastActionAt."
    }
    catch {
        # Not fatal. The work is done; only the memory of it is lost, and saying so is better than
        # failing a run that already deallocated machines correctly.
        Write-Output ('Dwell: could not write PM_LastActionAt, so the next run has no memory - ' +
            $_.Exception.Message)
    }
}

# Get-AutomationVariable hands a variable back as a Newtonsoft JObject, and a JObject indexes
# case-sensitively. The two catalogue variables were not written in the same case - Bicep writes
# name, older versions of this module wrote Name - so reading $entry.name found the deployment's
# entries and returned empty for every custom one. All of them keyed on an empty string, each
# replaced the last, and only one survived. A machine tagged with a lost schedule then reported
# ScheduleNotInCatalogue, which is indistinguishable from a machine nobody onboarded. Found by
# running it against a real Automation Account on 2026-09-11, with two custom schedules.
#
# The module writes camelCase now. This reads either, because a catalogue stored by an older
# version is still out there and would otherwise lose schedules quietly after an upgrade.
function Get-CatalogEntryName {
    param([Parameter()][AllowNull()]$Entry)

    if ($null -eq $Entry) { return '' }

    if ($Entry -is [System.Collections.IDictionary]) {
        foreach ($key in @($Entry.Keys)) { if ("$key" -eq 'name') { return [string]$Entry[$key] } }
    }

    foreach ($property in @($Entry.PSObject.Properties)) {
        if ($property.Name -eq 'name') { return [string]$property.Value }
    }

    # A JObject is not an IDictionary and exposes no PowerShell properties. Enumerating it yields
    # JProperty objects, which is the only way to reach its fields without guessing the casing.
    if ($Entry -is [System.Collections.IEnumerable] -and $Entry -isnot [string]) {
        foreach ($item in $Entry) {
            if ($null -eq $item) { continue }
            if ($item.PSObject.Properties['Name'] -and "$($item.Name)" -eq 'name') { return [string]$item.Value }
        }
    }

    ''
}

if (-not $ScheduleCatalog) {
    $merged = [ordered]@{}
    foreach ($variableName in 'PM_ScheduleCatalog', 'PM_ScheduleCatalogCustom') {
        $entries = ConvertTo-CatalogArray -Value (Get-StructuredSetting -Name $variableName)
        foreach ($entry in $entries) {
            if ($null -eq $entry) { continue }
            $entryName = Get-CatalogEntryName -Entry $entry
            # Never keyed on an empty string. That is what made three schedules out of four look
            # like a complete catalogue, and nothing downstream could tell the difference.
            if (-not $entryName) {
                throw ("An entry in the Automation variable $variableName has no readable name, so " +
                    'nothing was planned. A catalogue entry that cannot be keyed would silently ' +
                    'replace another one, and a schedule missing from the catalogue looks exactly ' +
                    'like a machine nobody onboarded.')
            }
            $merged[$entryName] = $entry
        }
    }
    if ($merged.Count) { $ScheduleCatalog = ConvertTo-Json -InputObject @($merged.Values) -Depth 8 -Compress }
}

$catalog = @()
if ($ScheduleCatalog) {
    $parsed = ConvertTo-CatalogArray -Value $ScheduleCatalog
    $checked = @($parsed | Test-VmPowerSchedule -Detailed)
    if (-not $checked.Count) { throw 'The schedule catalogue parsed to nothing. Check PM_ScheduleCatalog and PM_ScheduleCatalogCustom hold a JSON array of schedules.' }
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

$memory = ConvertTo-ActionMemory -Value (Get-StructuredSetting -Name 'PM_LastActionAt')
Write-Output "Dwell: $MinimumDwellMinutes min, $($memory.Count) machine(s) remembered from earlier runs"

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

# One machine-readable line per machine, alongside the readable one. The workbook parses these out
# of the job streams, which means no data collection rule, no custom table and no extra bill - and
# it means the evidence is the job log rather than a second thing that can disagree with it.
# The prefix is what makes the line findable in KQL; keep it stable.
function Write-Record {
    param(
        [Parameter(Mandatory)]$Item,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )
    $record = [ordered]@{
        t      = $runStarted
        run    = $runId
        armed  = $Armed
        vm     = [string]$Item.Name
        rg     = [string]$Item.ResourceGroup
        sub    = [string]$Item.SubscriptionId
        loc    = [string]$Item.Location
        size   = [string]$Item.VmSize
        state  = ([string]$Item.PowerState) -replace '^PowerState/', ''
        sched  = [string]$Item.Schedule
        action = [string]$Item.Action
        reason = [string]$Item.Reason
        status = $Status
    }
    Write-Output ("$script:RecordPrefix " + (ConvertTo-Json -InputObject $record -Depth 3 -Compress))
    Write-Output "[$($Item.Name)] $($Item.Action) - $Status`: $Detail"
}

$byId = @{}
foreach ($item in $plan) { $byId[[string]$item.Id] = $item }

# Disarmed is not a different code path. It is the same call with -WhatIf on it, so every guard is
# evaluated either way and a first week reports what arming it would have done - including a run it
# would have refused for exceeding the blast radius, which is worth finding while nothing is at
# stake rather than at the moment somebody sets PM_Armed to true.
$execute = @{
    MaximumActions      = $MaximumActions
    MinimumDwellMinutes = $MinimumDwellMinutes
    LastActionAt        = $memory
    Confirm             = $false
}
if (-not $Armed) { $execute['WhatIf'] = $true }

$acted = @{}
foreach ($result in ($plan | Invoke-VmPowerPlan @execute)) {
    $source = if ($byId.ContainsKey([string]$result.Id)) { $byId[[string]$result.Id] } else { $result }

    # A guard that fired is the interesting half of a dry run, and its own word for it - Skipped,
    # Failed - is what belongs in the record. Where none fired, the plan's reason says more than
    # the word WhatIf ever could.
    $noGuardFired = $result.Status -eq 'WhatIf' -or $source.Action -eq 'None'
    $status = if ($noGuardFired -and $source.Reason) { [string]$source.Reason } else { [string]$result.Status }

    Write-Record -Item $source -Status $status -Detail $result.Detail
    Add-Summary $status
    if ($result.Status -eq 'Done') { $acted[[string]$result.Id] = ([datetime]$result.Timestamp).ToUniversalTime().ToString('o') }

    if ($Armed) { $result } else { $source }
}

if ($Armed) {
    foreach ($id in $acted.Keys) { $memory[$id] = $acted[$id] }
    # Kept for as long as the longest dwell anyone asked for, and never less than an hour, so the
    # variable stays bounded whatever the settings say.
    $keepMinutes = $MinimumDwellMinutes
    foreach ($entry in $catalog) {
        if ([int]$entry.MinimumDwellMinutes -gt $keepMinutes) { $keepMinutes = [int]$entry.MinimumDwellMinutes }
    }
    Save-ActionMemory -Memory $memory -KeepMinutes ([Math]::Max($keepMinutes, 60))
}

Write-Output ('Summary: ' + $(if ($summary.Count) {
            ($summary.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', '
        }
        else { 'nothing to do' }))
