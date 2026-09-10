function Resolve-VmPowerAction {
    <#
    .SYNOPSIS
    Pure decision function: one machine in, one decision out.

    .DESCRIPTION
    Every rule this tool applies lives here, and nothing in here calls Azure. That is what makes
    the rules provable on fixtures, and it is what makes the dry run honest - the armed and
    disarmed paths compute the same decision and differ only in whether anybody acts on it.

    Rules are evaluated in order and the first match wins:

      1. An exclusion tag protects the machine, whatever else is true.
      2. A power state that cannot be read produces no action. Not knowing is not a reason to act.
      3. A transitional state (starting, stopping, deallocating) produces no action. Something is
         already happening to this machine.
      4. PowerState/stopped means allocated on a host, not running, and billed for compute. That
         is the machine to deallocate - see docs/decisions/0004.
      5. Anything else has no rule yet. Schedules arrive in the next slice.

    Rule 4 is the whole of version one, and it is deliberately the rule with no running workload
    to interrupt.

    .PARAMETER Machine
    One record from the Resource Graph inventory: id, name, powerState, tags.

    .PARAMETER ScheduleTag
    Tag key that opts a machine in. Its value names a schedule; version one only needs its presence.

    .PARAMETER ExclusionTag
    Tag key that protects a machine from every rule.

    .PARAMETER IncludeUntagged
    Allow a decision on a machine carrying no schedule tag. Off by default, because opt-in is the
    rule (docs/decisions/0004) and a machine nobody has thought about is one nobody has decided
    about. A stranded machine is still reported when this is off; it is reported as not onboarded.
    #>
    [CmdletBinding()]
    [OutputType('AzureVMPowerManagement.VmPowerPlan')]
    param(
        [Parameter(Mandatory)]
        $Machine,

        [Parameter()]
        [string]$ScheduleTag = 'PowerSchedule',

        [Parameter()]
        [string]$ExclusionTag = 'PowerSchedule-Exclude',

        [Parameter()]
        [switch]$IncludeUntagged
    )

    $id = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'id' -Default '')
    $name = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'name' -Default '(unnamed)')
    $powerState = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'powerState' -Default '')
    $tags = Get-PropertyOrDefault -InputObject $Machine -Name 'tags' -Default @{}

    # Azure is inconsistent about the case of a tag key, and Resource Graph hands tags back as a
    # PSCustomObject from Search-AzGraph and as a hashtable from a fixture. A lookup that misses
    # reads as "not tagged", which here would mean acting on a machine somebody excluded - so both
    # shapes are flattened into one case-insensitive table before anything is asked of them.
    $tagLookup = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($tags -is [System.Collections.IDictionary]) {
        foreach ($key in @($tags.Keys)) { $tagLookup[[string]$key] = [string]$tags[$key] }
    }
    elseif ($null -ne $tags) {
        foreach ($property in @($tags.PSObject.Properties)) { $tagLookup[$property.Name] = [string]$property.Value }
    }

    $schedule = if ($tagLookup.ContainsKey($ScheduleTag)) { $tagLookup[$ScheduleTag] } else { '' }
    $excluded = $tagLookup.ContainsKey($ExclusionTag)

    $action, $reason, $explanation = switch ($true) {
        $excluded {
            'None', 'Excluded', "Carries the $ExclusionTag tag, so no rule applies to it."
            break
        }
        ([string]::IsNullOrWhiteSpace($powerState)) {
            'None', 'PowerStateUnknown', 'Resource Graph returned no power state for this machine. Not knowing is not a reason to act.'
            break
        }
        ($powerState -in $script:TransitionalPowerStates) {
            'None', 'InTransition', "Power state is $powerState, so something is already happening to this machine."
            break
        }
        ($powerState -eq $script:PowerState.Stopped) {
            if ($schedule -or $IncludeUntagged) {
                'Deallocate', 'StoppedNotDeallocated', 'Powered off but still allocated on a host, so still billed for compute. Deallocating it interrupts nothing that is running.'
            }
            else {
                'None', 'StrandedButNotOnboarded', "Powered off but still allocated, so still billed for compute. It carries no $ScheduleTag tag, so it is reported rather than acted on."
            }
            break
        }
        default {
            'None', 'NoRuleMatched', "Power state is $powerState and no rule in this version covers it."
        }
    }

    [pscustomobject]@{
        PSTypeName      = $script:TypeName.Plan
        Id              = $id
        Name            = $name
        ResourceGroup   = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'resourceGroup' -Default '')
        SubscriptionId  = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'subscriptionId' -Default '')
        Location        = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'location' -Default '')
        VmSize          = [string](Get-PropertyOrDefault -InputObject $Machine -Name 'vmSize' -Default '')
        PowerState      = $powerState
        Schedule        = if ($schedule) { $schedule } else { '' }
        Action          = $action
        Reason          = $reason
        Explanation     = $explanation
        Protected       = [bool]$excluded
        ProtectedReason = if ($excluded) { "Excluded by the $ExclusionTag tag" } else { '' }
    }
}
