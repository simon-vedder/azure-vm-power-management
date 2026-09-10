# Remove-VmPowerPlan

> Remove what a VmPowerPlan finding points at, after backing it up.

Skeleton example of the write path every tool in this family shares:

  - accepts the objects Get-VmPowerPlan produced, never free-form names
  - writes a JSON backup of every object before touching it (-BackupPath)
  - SupportsShouldProcess with ConfirmImpact High: a prompt per object, -WhatIf everywhere
  - refuses objects marked Protected (break-glass, PIM-managed) and reports them instead

The tool proposes, the administrator decides. Replace the body of the "act" block with the
real Az or Graph call and keep everything around it.

## Syntax

```powershell
Remove-VmPowerPlan [-InputObject] <VmPowerPlan[]> [[-BackupPath] <string>] [-WhatIf] [-Confirm] [<CommonParameters>]
```

## Requirements and notes

Required permissions: write. Name the exact scope or action here; the read path must not need it.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-InputObject` | Object[] | yes | yes |  | Findings from Get-VmPowerPlan. |
| `-BackupPath` | String | no | no | (Join-Path (Get-Location) ('AzureVMPowerManagement-backup-{0:yyyyMMdd-HHmmss}.json' -f (Get-Date))) | JSON file that receives every object before it is removed. Default: ./AzureVMPowerManagement-backup-<timestamp>.json in the current directory. |

Supports `-WhatIf` and `-Confirm`.

## Examples

### Example 1

```powershell
Get-VmPowerPlan -MinimumSeverity High | Remove-VmPowerPlan -WhatIf
```

### Example 2

```powershell
Get-VmPowerPlan | Out-ConsoleGridView -PassThru | Remove-VmPowerPlan
```

## Output

- AzureVMPowerManagement.VmPowerPlanRemoval

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
