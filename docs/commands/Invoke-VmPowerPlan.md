# Invoke-VmPowerPlan

> Carry out a plan, after the guards agree to it

Takes the decisions Get-VmPowerPlan produced and performs the ones the guards allow. The plan
is computed once and consumed here, so an armed run and a dry run cannot drift apart.

Four guards stand between a plan and a machine, and all four refuse loudly rather than quietly:

  Confirm       Every action goes through ShouldProcess, so -WhatIf previews the whole run.
  Protected     A machine carrying the exclusion tag is never touched, whatever the plan says.
  Blast radius  A run that would act on more machines than -MaximumActions performs none of
                them. A mistake broad enough to matter becomes a report, not an incident.
  Dwell         A machine acted on within -MinimumDwellMinutes is left alone. Azure bills a
                five-minute minimum per start, so a flapping schedule costs money as well as
                being wrong.

Deallocation is the only action version one performs, and it uses Stop-AzVM, which requests a
graceful shutdown and then releases the host. A machine already in PowerState/stopped has no
running operating system to shut down, so in practice this is a pure deallocate.

## Syntax

```powershell
Invoke-VmPowerPlan [-Plan] <VmPowerPlan[]> [-MaximumActions] <int> [[-MinimumDwellMinutes] <int>] [[-LastActionAt] <hashtable>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

RequiredPermissions: Microsoft.Compute/virtualMachines/deallocate/action and
Microsoft.Compute/virtualMachines/read on every machine in scope, or their resource groups.
Virtual Machine Contributor covers both and a great deal more, so a custom role limited to
those two actions plus Microsoft.Compute/virtualMachines/start/action is the narrower choice
and is what deploy/main.bicep creates.

Prerequisites: PowerShell 7.2 or later, and the modules Az.Accounts and Az.Compute.

Writes: Deallocates virtual machines. This is the command that can cost somebody an outage,
which is why every guard above defaults to refusing.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-Plan` | Object[] | yes | yes |  | Decisions from Get-VmPowerPlan. Items with an action of None are counted and skipped. |
| `-MaximumActions` | Int32 | yes | no | 0 | Refuse the entire run if more than this many machines would be acted on. There is no default that is right for somebody else's estate, so this is mandatory. |
| `-MinimumDwellMinutes` | Int32 | no | no | 30 | Leave a machine alone if it changed power state more recently than this. Zero disables the check. |
| `-LastActionAt` | Hashtable | no | no | @{} | Map of resource id to the time this tool last acted on it, for the dwell check. The runbook passes what it recorded on the previous run. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
# Preview everything an armed run would do, and change nothing
Get-VmPowerPlan -ActionableOnly | Invoke-VmPowerPlan -MaximumActions 50 -WhatIf
```

### Example 2

```powershell
# Deallocate the machines that are powered off and still billed, at most twenty of them
Get-VmPowerPlan -ActionableOnly | Invoke-VmPowerPlan -MaximumActions 20
```

## Output

- AzureVMPowerManagement.VmPowerPlanResult

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
