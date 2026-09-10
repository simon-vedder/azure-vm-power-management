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
         is the machine to deallocate, and it wins over the schedule: somebody already shut this
         machine down, so the only question left is whether to keep paying for it. The next
         scheduled start brings it back if the schedule says so.
      5. The schedule decides. Up and deallocated starts it; Down and running deallocates it;
         anything already in the state the schedule wants is left alone.
      6. No schedule and nothing stranded means no rule applies.

    Rule 4 is the one with no running workload to interrupt, which is why it is the rule that ships
    first and the rule that can be armed first.

    .PARAMETER Machine
    One record from the Resource Graph inventory: id, name, powerState, tags.

    .PARAMETER ScheduleTag
    Tag key that opts a machine in. Its value names a schedule; version one only needs its presence.

    .PARAMETER ExclusionTag
    Tag key that protects a machine from every rule.

    .PARAMETER ScheduleState
    Desired state per schedule name, as Get-VmPowerScheduleState works it out: State, how many
    minutes ago the schedule last acted, and the schedule's start grace. Computed once per schedule
    by the caller rather than per machine, because a thousand machines usually share a handful of
    schedules.

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
        [hashtable]$ScheduleState = @{},

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
        ($schedule -and $ScheduleState.ContainsKey($schedule)) {
            $desired = $ScheduleState[$schedule]
            $wanted = [string]$desired.State
            $sinceMinutes = [int]$desired.MinutesSince
            $grace = [int]$desired.StartGraceMinutes
            switch ($true) {
                ($wanted -eq 'Up' -and $powerState -eq $script:PowerState.Deallocated -and $sinceMinutes -le $grace) {
                    'Start', 'ShouldBeRunning', "Schedule '$schedule' started machines $sinceMinutes minute(s) ago and this one is deallocated, so the start did not take."
                    break
                }
                ($wanted -eq 'Up' -and $powerState -eq $script:PowerState.Deallocated) {
                    'None', 'DownSinceTheStartWindow', "Schedule '$schedule' wants it up, but its start was $sinceMinutes minute(s) ago, past the $grace minute grace. A machine that has been down that long was turned off on purpose - see docs/decisions/0007."
                    break
                }
                ($wanted -eq 'Down' -and $powerState -eq $script:PowerState.Running) {
                    'Deallocate', 'ShouldBeStopped', "Schedule '$schedule' has it down at this time and it is running."
                    break
                }
                ($wanted -eq 'Unknown') {
                    'None', 'ScheduleStateUnknown', "Schedule '$schedule' has no action in the lookback window, so there is nothing to compare against."
                    break
                }
                default {
                    'None', 'MatchesSchedule', "Already $powerState, which is what schedule '$schedule' wants at this time."
                }
            }
            break
        }
        # [bool] is not decoration. switch ($true) does not coerce the way -eq does: $true -eq
        # 'office-hours-ch' is True, but ('office-hours-ch') as a case label never matches, because
        # switch compares the case value against the switch value as a string. Written without the
        # cast this branch is dead and the machine falls through to a reason that is not true.
        ([bool]$schedule) {
            'None', 'ScheduleNotInCatalogue', "The tag names the schedule '$schedule', which is not in the catalogue this run was given. A machine is not acted on by a rule nobody can read."
            break
        }
        default {
            'None', 'NoRuleMatched', "Power state is $powerState, the machine carries no schedule, and nothing else applies."
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
