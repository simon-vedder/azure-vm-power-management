# Get-VmPowerPlan

> Read-only discovery of VmPowerPlan findings.

Skeleton example of the read path. Replace the source (here the -InputObject parameter) with
the Az or Graph calls the tool needs and keep the shape: collect raw facts, hand each one to a
pure decision function in Private/, emit typed objects. Nothing in this function changes state.

## Syntax

```powershell
Get-VmPowerPlan [[-InputObject] <Object[]>] [[-MinimumSeverity] <string>] [<CommonParameters>]
```

## Requirements and notes

Required permissions: read-only. List the exact Graph scopes or RBAC actions here, and in the
README's Permissions section.

## Parameters

| Name | Type | Required | Pipeline | Default | Description |
|---|---|---|---|---|---|
| `-InputObject` | Object[] | no | yes |  | Raw records to evaluate. In a real tool this is what Get-AzRoleAssignment, Get-MgApplication and friends return. |
| `-MinimumSeverity` | String | no | no | Info | Return only findings at or above this severity. |

## Examples

### Example 1

```powershell
Get-VmPowerPlan | Format-Table Name, Severity, Reason
```

### Example 2

```powershell
Get-VmPowerPlan -MinimumSeverity High | Remove-VmPowerPlan -WhatIf
```

## Output

- AzureVMPowerManagement.VmPowerPlan

---

[All commands](README.md) | [Module README](../../README.md)

*Generated from the comment-based help by `tools/New-CommandReference.ps1`. Edit the help in the function, not this file.*
